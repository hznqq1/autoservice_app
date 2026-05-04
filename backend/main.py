from datetime import datetime
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select
from sqlalchemy.orm import Session

from .database import Base, SessionLocal, engine
from .models import Booking, Car, Service
from .schemas import (
    BookingCreate,
    BookingOut,
    BookingStatusUpdate,
    CarCreate,
    CarOut,
    CarUpdate,
    ServiceOut,
)

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


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@app.on_event("startup")
def init_db() -> None:
    Base.metadata.create_all(bind=engine)
    with SessionLocal() as db:
        has_services = db.scalar(select(Service.id).limit(1))
        if not has_services:
            for service in DEFAULT_SERVICES:
                db.add(Service(name=service["name"], price=service["price"]))
            db.commit()


@app.get("/health")
def health():
    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}


@app.get("/services", response_model=list[ServiceOut])
def list_services(db: Session = Depends(get_db)):
    return db.scalars(select(Service).order_by(Service.id)).all()


@app.get("/cars", response_model=list[CarOut])
def list_cars(db: Session = Depends(get_db)):
    return db.scalars(select(Car).order_by(Car.id)).all()


@app.post("/cars", response_model=CarOut)
def create_car(payload: CarCreate, db: Session = Depends(get_db)):
    car = Car(brand=payload.brand.strip(), number=payload.number.strip().upper(), note=payload.note.strip())
    db.add(car)
    db.commit()
    db.refresh(car)
    return car


@app.put("/cars/{car_id}", response_model=CarOut)
def update_car(car_id: int, payload: CarUpdate, db: Session = Depends(get_db)):
    car = db.get(Car, car_id)
    if not car:
        raise HTTPException(status_code=404, detail="Car not found")
    car.brand = payload.brand.strip()
    car.number = payload.number.strip().upper()
    car.note = payload.note.strip()
    db.commit()
    db.refresh(car)
    return car


@app.delete("/cars/{car_id}")
def delete_car(car_id: int, db: Session = Depends(get_db)):
    car = db.get(Car, car_id)
    if not car:
        raise HTTPException(status_code=404, detail="Car not found")
    db.delete(car)
    db.commit()
    return {"status": "deleted"}


def map_booking(booking: Booking) -> BookingOut:
    total = sum(service.price for service in booking.services)
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
    )


@app.get("/bookings", response_model=list[BookingOut])
def list_bookings(db: Session = Depends(get_db)):
    bookings = db.scalars(select(Booking).order_by(Booking.created_at.desc())).all()
    return [map_booking(booking) for booking in bookings]


@app.post("/bookings", response_model=BookingOut)
def create_booking(payload: BookingCreate, db: Session = Depends(get_db)):
    car = db.get(Car, payload.car_id)
    if not car:
        raise HTTPException(status_code=404, detail="Car not found")
    if not payload.service_ids:
        raise HTTPException(status_code=400, detail="At least one service is required")

    services = db.scalars(select(Service).where(Service.id.in_(payload.service_ids))).all()
    if len(services) != len(set(payload.service_ids)):
        raise HTTPException(status_code=400, detail="One or more service IDs are invalid")

    booking = Booking(car_id=car.id, complaint=payload.complaint.strip(), status="Ожидание")
    booking.services = services
    total = sum(service.price for service in services)
    car.total_spent += total

    db.add(booking)
    db.commit()
    db.refresh(booking)
    return map_booking(booking)


@app.patch("/bookings/{booking_id}/status", response_model=BookingOut)
def update_booking_status(
    booking_id: int,
    payload: BookingStatusUpdate,
    db: Session = Depends(get_db),
):
    booking = db.get(Booking, booking_id)
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")
    booking.status = payload.status
    db.commit()
    db.refresh(booking)
    return map_booking(booking)