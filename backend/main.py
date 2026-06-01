import os
from datetime import datetime

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, text
from sqlalchemy.orm import Session, joinedload

from .auth import (
    create_access_token,
    get_client_car,
    get_current_user,
    get_db,
    hash_password,
    verify_password,
)
from .database import Base, SessionLocal, engine
from .models import Booking, Car, Service, User
from .schemas import (
    AuthUserOut,
    BookingCreate,
    BookingOut,
    BookingStatusUpdate,
    CarCreate,
    CarOut,
    CarUpdate,
    ServiceOut,
    UserLogin,
    UserRegister,
)

MECHANIC_EMAIL = os.getenv("MECHANIC_EMAIL", "mechanic@trio.ru")
MECHANIC_PASSWORD = os.getenv("MECHANIC_PASSWORD", "mechanic123")
LEGACY_MECHANIC_EMAIL = "mechanic@trio.local"

app = FastAPI(title="AutoService API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


DEFAULT_SERVICES = [
    {"name": "Замена масла в двигателе", "price": 1500},
    {"name": "Компьютерная диагностика", "price": 2500},
    {"name": "Ремонт ходовой части", "price": 4000},
    {"name": "Замена тормозных колодок", "price": 1200},
    {"name": "Обслуживание кондиционера", "price": 2000},
    {"name": "Сход-развал (3D)", "price": 1800},
    {"name": "Шиномонтаж комплексный", "price": 2000},
    {"name": "Замена свечей зажигания", "price": 1000},
]


def _auth_user_out(user: User) -> AuthUserOut:
    return AuthUserOut(
        id=user.id,
        email=user.email,
        role=user.role,
        access_token=create_access_token(user.id, user.role),
    )


def _booking_client_email(booking: Booking) -> str:
    if booking.owner:
        return booking.owner.email
    if booking.car and booking.car.owner:
        return booking.car.owner.email
    return "—"


@app.on_event("startup")
def init_db() -> None:
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
        conn.execute(
            text(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS "
                "role VARCHAR(20) NOT NULL DEFAULT 'client'"
            )
        )
        conn.execute(
            text(
                "ALTER TABLE cars ADD COLUMN IF NOT EXISTS "
                "user_id INTEGER REFERENCES users(id)"
            )
        )
        conn.execute(
            text(
                "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS "
                "user_id INTEGER REFERENCES users(id)"
            )
        )
    with SessionLocal() as db:
        has_services = db.scalar(select(Service.id).limit(1))
        if not has_services:
            for service in DEFAULT_SERVICES:
                db.add(Service(name=service["name"], price=service["price"]))
            db.commit()

        legacy_mechanic = db.scalar(select(User).where(User.email == LEGACY_MECHANIC_EMAIL))
        if legacy_mechanic:
            legacy_mechanic.email = MECHANIC_EMAIL
            legacy_mechanic.role = "mechanic"
            legacy_mechanic.hashed_password = hash_password(MECHANIC_PASSWORD)
            db.commit()

        mechanic = db.scalar(select(User).where(User.email == MECHANIC_EMAIL))
        if not mechanic:
            db.add(
                User(
                    email=MECHANIC_EMAIL,
                    hashed_password=hash_password(MECHANIC_PASSWORD),
                    role="mechanic",
                )
            )
            db.commit()
        else:
            if mechanic.role != "mechanic":
                mechanic.role = "mechanic"
            mechanic.hashed_password = hash_password(MECHANIC_PASSWORD)
            db.commit()


@app.get("/health")
def health():
    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}


@app.post("/register", response_model=AuthUserOut, status_code=201)
def register(payload: UserRegister, db: Session = Depends(get_db)):
    email = payload.email.strip().lower()
    existing = db.scalar(select(User).where(User.email == email))
    if existing:
        raise HTTPException(status_code=400, detail="Этот email уже зарегистрирован")

    user = User(
        email=email,
        hashed_password=hash_password(payload.password),
        role="client",
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return _auth_user_out(user)


@app.post("/login", response_model=AuthUserOut)
def login(payload: UserLogin, db: Session = Depends(get_db)):
    email = payload.email.strip().lower()
    user = db.scalar(select(User).where(User.email == email))
    if not user or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Неверный email или пароль")
    return _auth_user_out(user)


@app.get("/services", response_model=list[ServiceOut])
def list_services(db: Session = Depends(get_db)):
    return db.scalars(select(Service).order_by(Service.id)).all()


@app.get("/cars", response_model=list[CarOut])
def list_cars(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role == "mechanic":
        raise HTTPException(status_code=403, detail="Доступ только для клиентов")
    cars = db.scalars(
        select(Car).where(Car.user_id == current_user.id).order_by(Car.id)
    ).all()
    return cars


@app.post("/cars", response_model=CarOut)
def create_car(
    payload: CarCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role != "client":
        raise HTTPException(status_code=403, detail="Доступ только для клиентов")
    car = Car(
        user_id=current_user.id,
        brand=payload.brand.strip(),
        number=payload.number.strip().upper(),
        note=payload.note.strip(),
    )
    db.add(car)
    db.commit()
    db.refresh(car)
    return car


@app.put("/cars/{car_id}", response_model=CarOut)
def update_car(
    car_id: int,
    payload: CarUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    car = get_client_car(car_id, current_user, db)
    car.brand = payload.brand.strip()
    car.number = payload.number.strip().upper()
    car.note = payload.note.strip()
    db.commit()
    db.refresh(car)
    return car


@app.delete("/cars/{car_id}")
def delete_car(
    car_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    car = get_client_car(car_id, current_user, db)
    db.delete(car)
    db.commit()
    return {"status": "deleted"}


def map_booking(booking: Booking) -> BookingOut:
    total = sum(service.price for service in booking.services)
    client = booking.owner or (booking.car.owner if booking.car else None)
    return BookingOut(
        id=booking.id,
        car_id=booking.car_id,
        car=booking.car.brand,
        num=booking.car.number,
        services=", ".join(service.name for service in booking.services),
        service_ids=[service.id for service in booking.services],
        price=total,
        complaint=booking.complaint,
        status=booking.status,
        date=booking.created_at.strftime("%d.%m.%Y %H:%M"),
        created_at=booking.created_at,
        client_email=_booking_client_email(booking),
        client_id=client.id if client else None,
    )


def _bookings_query():
    return (
        select(Booking)
        .options(
            joinedload(Booking.car).joinedload(Car.owner),
            joinedload(Booking.owner),
            joinedload(Booking.services),
        )
        .order_by(Booking.created_at.desc())
    )


@app.get("/bookings", response_model=list[BookingOut])
def list_bookings(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    query = _bookings_query()
    if current_user.role == "client":
        query = query.where(Booking.user_id == current_user.id)
    bookings = db.scalars(query).unique().all()
    return [map_booking(booking) for booking in bookings]


@app.post("/bookings", response_model=BookingOut)
def create_booking(
    payload: BookingCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role != "client":
        raise HTTPException(status_code=403, detail="Доступ только для клиентов")

    car = get_client_car(payload.car_id, current_user, db)
    if not payload.service_ids:
        raise HTTPException(status_code=400, detail="At least one service is required")

    services = db.scalars(select(Service).where(Service.id.in_(payload.service_ids))).all()
    if len(services) != len(set(payload.service_ids)):
        raise HTTPException(status_code=400, detail="One or more service IDs are invalid")

    booking = Booking(
        user_id=current_user.id,
        car_id=car.id,
        complaint=payload.complaint.strip(),
        status="Ожидание",
    )
    booking.services = services
    total = sum(service.price for service in services)
    car.total_spent += total

    db.add(booking)
    db.commit()
    booking_id = booking.id
    booking = db.scalar(_bookings_query().where(Booking.id == booking_id))
    return map_booking(booking)


@app.patch("/bookings/{booking_id}/status", response_model=BookingOut)
def update_booking_status(
    booking_id: int,
    payload: BookingStatusUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role != "mechanic":
        raise HTTPException(status_code=403, detail="Доступ только для механика")

    booking = db.scalar(_bookings_query().where(Booking.id == booking_id))
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")
    booking.status = payload.status
    db.commit()
    booking = db.scalar(_bookings_query().where(Booking.id == booking_id))
    return map_booking(booking)
