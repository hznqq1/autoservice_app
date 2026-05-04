from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field


class ServiceOut(BaseModel):
    id: int
    name: str
    price: int

    model_config = ConfigDict(from_attributes=True)


class CarCreate(BaseModel):
    brand: str = Field(min_length=1, max_length=120)
    number: str = Field(min_length=1, max_length=32)
    note: str = ""


class CarUpdate(BaseModel):
    brand: str = Field(min_length=1, max_length=120)
    number: str = Field(min_length=1, max_length=32)
    note: str = ""


class CarOut(BaseModel):
    id: int
    brand: str
    number: str
    total_spent: int
    note: str

    model_config = ConfigDict(from_attributes=True)


class BookingCreate(BaseModel):
    car_id: int
    service_ids: list[int]
    complaint: str = ""


class BookingStatusUpdate(BaseModel):
    status: str = Field(pattern="^(Ожидание|В работе|Готово)$")


class BookingOut(BaseModel):
    id: int
    car_id: int
    car: str
    num: str
    services: str
    service_ids: list[int]
    price: int
    complaint: str
    status: str
    date: str
    created_at: datetime
