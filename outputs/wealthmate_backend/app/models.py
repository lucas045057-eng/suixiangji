from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import JSON, Boolean, Date, DateTime, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    username: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(256))
    display_name: Mapped[str] = mapped_column(String(128), default="财富用户")
    quick_memories: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    auth_version: Mapped[int] = mapped_column(Integer, default=0)
    sync_version: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class Account(Base):
    __tablename__ = "accounts"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    name: Mapped[str] = mapped_column(String(128))
    kind: Mapped[str] = mapped_column(String(32), default="asset")
    account_kind: Mapped[str] = mapped_column(String(32), default="other")
    currency: Mapped[str] = mapped_column(String(16), default="CNY")
    opening_balance: Mapped[Decimal] = mapped_column(Numeric(20, 6), default=0)
    opening_cny_amount: Mapped[Decimal | None] = mapped_column(Numeric(20, 6), nullable=True)
    opening_exchange_rate: Mapped[Decimal | None] = mapped_column(Numeric(20, 10), nullable=True)
    opening_rate_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    opening_rate_source: Mapped[str | None] = mapped_column(String(256), nullable=True)
    is_liquid: Mapped[bool] = mapped_column(Boolean, default=False)
    is_default_payment: Mapped[bool] = mapped_column(Boolean, default=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    server_version: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class Category(Base):
    __tablename__ = "categories"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    name: Mapped[str] = mapped_column(String(128))
    kind: Mapped[str] = mapped_column(String(32), default="expense")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    server_version: Mapped[int] = mapped_column(Integer, default=0, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class Transaction(Base):
    __tablename__ = "transactions"
    __table_args__ = (UniqueConstraint("user_id", "client_op_id", name="uq_transaction_client_op"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    client_op_id: Mapped[str] = mapped_column(String(128))
    kind: Mapped[str] = mapped_column(String(32))
    amount: Mapped[Decimal] = mapped_column(Numeric(20, 6))
    currency: Mapped[str] = mapped_column(String(16), default="CNY")
    cny_amount: Mapped[Decimal | None] = mapped_column(Numeric(20, 6), nullable=True)
    exchange_rate: Mapped[Decimal | None] = mapped_column(Numeric(20, 10), nullable=True)
    exchange_rate_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    exchange_rate_source: Mapped[str | None] = mapped_column(String(256), nullable=True)
    conversion_status: Mapped[str] = mapped_column(String(32), default="ready")
    category_id: Mapped[str | None] = mapped_column(ForeignKey("categories.id"), nullable=True)
    category_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), nullable=True)
    from_account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), nullable=True)
    to_account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id"), nullable=True)
    occurred_on: Mapped[date] = mapped_column(Date, index=True)
    occurred_at: Mapped[str | None] = mapped_column(String(64), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    server_version: Mapped[int] = mapped_column(Integer, default=0, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class SyncOperation(Base):
    __tablename__ = "sync_operations"
    __table_args__ = (UniqueConstraint("user_id", "client_op_id", name="uq_sync_client_op"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    client_op_id: Mapped[str] = mapped_column(String(128))
    entity: Mapped[str] = mapped_column(String(64))
    entity_id: Mapped[str] = mapped_column(String(64))
    server_version: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class ExchangeRate(Base):
    __tablename__ = "exchange_rates"
    __table_args__ = (UniqueConstraint("base_currency", "quote_currency", "rate_date", "source", name="uq_exchange_snapshot"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    base_currency: Mapped[str] = mapped_column(String(16))
    quote_currency: Mapped[str] = mapped_column(String(16), default="CNY")
    rate: Mapped[Decimal] = mapped_column(Numeric(20, 10))
    rate_date: Mapped[date] = mapped_column(Date)
    source: Mapped[str] = mapped_column(String(256))
    fetched_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class Budget(Base):
    __tablename__ = "budgets"
    __table_args__ = (UniqueConstraint("user_id", "month", "category_id", name="uq_budget_user_month_category"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    month: Mapped[str] = mapped_column(String(7), index=True)
    category_id: Mapped[str] = mapped_column(String(64))
    limit: Mapped[Decimal] = mapped_column(Numeric(20, 6))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    server_version: Mapped[int] = mapped_column(Integer, default=0, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class NetWorthSnapshot(Base):
    __tablename__ = "net_worth_snapshots"
    __table_args__ = (UniqueConstraint("user_id", "month", name="uq_net_worth_month"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    month: Mapped[str] = mapped_column(String(7))
    total_assets_cny: Mapped[Decimal | None] = mapped_column(Numeric(20, 6), nullable=True)
    total_liabilities_cny: Mapped[Decimal | None] = mapped_column(Numeric(20, 6), nullable=True)
    net_worth_cny: Mapped[Decimal | None] = mapped_column(Numeric(20, 6), nullable=True)
    pending_conversion_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class MonthlyReport(Base):
    __tablename__ = "monthly_reports"
    __table_args__ = (UniqueConstraint("user_id", "month", name="uq_report_month"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    month: Mapped[str] = mapped_column(String(7))
    metrics: Mapped[dict[str, Any]] = mapped_column(JSON)
    narrative: Mapped[str] = mapped_column(Text)
    ai_status: Mapped[str] = mapped_column(String(32), default="unavailable")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class AgentLog(Base):
    __tablename__ = "agent_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    task: Mapped[str] = mapped_column(String(64))
    model: Mapped[str | None] = mapped_column(String(128), nullable=True)
    status: Mapped[str] = mapped_column(String(32))
    input_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    output_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cost: Mapped[Decimal | None] = mapped_column(Numeric(20, 8), nullable=True)
    result_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
