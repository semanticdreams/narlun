import sqlalchemy as sa
from geoalchemy2 import Geography
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import relationship, backref
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql import func

import config


Base = declarative_base()
db = sa.create_engine(config.DATABASE_URL, echo=True, future=True)


user_roles = sa.Table(
    'user_roles',
    Base.metadata,
    sa.Column(
        'user_id',
        sa.Integer(),
        sa.ForeignKey(
            'users.id',
            ondelete='CASCADE')),
    sa.Column(
        'role_id',
        sa.Integer(),
        sa.ForeignKey(
            'roles.id',
            ondelete='CASCADE'))
)


class Role(Base):
    __tablename__ = 'roles'
    id = sa.Column(sa.Integer, primary_key=True)
    name = sa.Column(sa.String(50), unique=True)


class User(Base):
    __tablename__ = 'users'
    id = sa.Column(sa.Integer, primary_key=True)
    email = sa.Column(sa.String(120), index=True, unique=True)
    # email = sa.Column(sa.String(255), nullable=False, unique=True)
    password_hash = sa.Column(sa.String(128))
    about_me = sa.Column(sa.Text)
    phone = sa.Column(sa.String(64))
    last_seen = sa.Column(sa.DateTime, server_default=func.now())
    # confirmed_at = sa.Column(sa.DateTime())
    roles = relationship('Role', secondary=user_roles,
                         backref=backref('users', lazy='dynamic'))
    token = sa.Column(sa.String(32), index=True, unique=True)
    token_expiration = sa.Column(sa.DateTime)
    notifications = relationship('Notification', backref='user',
                                 lazy='dynamic')
    username = sa.Column(sa.String(40), index=True, unique=True)
    picture = sa.Column(sa.String(255))

    last_geog = sa.Column(Geography('POINT'))

    __table_args__ = (
        sa.Index('user_last_geog_gist', last_geog, postgresql_using='gist'),
    )


class Room(Base):
    __tablename__ = 'rooms'
    id = sa.Column(sa.Integer, primary_key=True)
    name = sa.Column(sa.String(34), unique=True)
    last_message = sa.Column(postgresql.JSONB)
    updated_at = sa.Column(sa.DateTime, index=True, server_default=func.now())
    picture = sa.Column(sa.String(255))
    is_group = sa.Column(sa.Boolean, server_default='false')
    is_public = sa.Column(sa.Boolean, server_default='false')


class Participants(Base):
    __tablename__ = 'participants'
    room_id = sa.Column(sa.Integer, sa.ForeignKey('rooms.id', ondelete='CASCADE'), primary_key=True)
    user_id = sa.Column(sa.Integer, sa.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True)


class Message(Base):
    __tablename__ = 'messages'
    id = sa.Column(sa.Integer, primary_key=True)
    sender_id = sa.Column(sa.Integer, sa.ForeignKey('users.id', ondelete='CASCADE'))
    room_id = sa.Column(sa.Integer, sa.ForeignKey('rooms.id', ondelete='CASCADE'))
    body = sa.Column(sa.Text)
    timestamp = sa.Column(sa.DateTime, index=True, server_default=func.now())


class Notification(Base):
    __tablename__ = 'notification'
    id = sa.Column(sa.Integer, primary_key=True)
    name = sa.Column(sa.String(128), index=True)
    user_id = sa.Column(sa.Integer,
                        sa.ForeignKey('users.id', ondelete='CASCADE'))
    timestamp = sa.Column(sa.DateTime, index=True, server_default=func.now())
    payload_json = sa.Column(postgresql.JSONB())
    seen = sa.Column(sa.Boolean, server_default='false', index=True)


class UserCheckIn(Base):
    __tablename__ = 'user_checkins'
    id = sa.Column(sa.Integer, primary_key=True)

    user_id = sa.Column(sa.Integer,
                        sa.ForeignKey('users.id', ondelete='CASCADE'))
    timestamp = sa.Column(sa.DateTime, index=True, server_default=func.now())

    geog = sa.Column(Geography('POINT'))

    __table_args__ = (
        sa.Index('user_checkins_geog_gist', geog, postgresql_using='gist'),
    )
