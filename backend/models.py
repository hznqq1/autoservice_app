from datetime import datetime
from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Table,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base

booking_services = Table(
    "booking_services",
    Base.metadata,
    Column("booking_id", ForeignKey("bookings.id"), primary_key=True),
    Column("service_id", ForeignKey("services.id"), primary_key=True),
)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(String(20), default="client", nullable=False)

    cars: Mapped[list["Car"]] = relationship("Car", back_populates="owner")
    bookings: Mapped[list["Booking"]] = relationship("Booking", back_populates="owner")


class Car(Base):
    __tablename__ = "cars"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    brand: Mapped[str] = mapped_column(String(120), nullable=False)
    number: Mapped[str] = mapped_column(String(32), nullable=False)
    total_spent: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    note: Mapped[str] = mapped_column(Text, default="", nullable=False)

    owner: Mapped["User | None"] = relationship("User", back_populates="cars")
    bookings: Mapped[list["Booking"]] = relationship("Booking", back_populates="car")


class Service(Base):
    __tablename__ = "services"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    price: Mapped[int] = mapped_column(Integer, nullable=False)

    bookings: Mapped[list["Booking"]] = relationship(
        "Booking",
        secondary=booking_services,
        back_populates="services",
    )


class Booking(Base):
    __tablename__ = "bookings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    car_id: Mapped[int] = mapped_column(ForeignKey("cars.id"), nullable=False)
    complaint: Mapped[str] = mapped_column(Text, default="", nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="Ожидание", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    owner: Mapped["User | None"] = relationship("User", back_populates="bookings")
    car: Mapped["Car"] = relationship("Car", back_populates="bookings")
    services: Mapped[list["Service"]] = relationship(
        "Service",
        secondary=booking_services,
        back_populates="bookings",
    )
