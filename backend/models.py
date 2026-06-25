from sqlalchemy import create_engine, Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import declarative_base, relationship, sessionmaker
from datetime import datetime
from config import DB_PATH

Base = declarative_base()

class Course(Base):
    __tablename__ = "courses"
    
    id = Column(Integer, primary_key=True)
    moodle_id = Column(String, unique=True, nullable=False)
    name = Column(String, nullable=False)
    short_name = Column(String)
    url = Column(String)
    
    tasks = relationship("Task", back_populates="course", cascade="all, delete-orphan")

class Task(Base):
    __tablename__ = "tasks"
    
    id = Column(Integer, primary_key=True)
    moodle_id = Column(String, unique=True, nullable=False)
    course_id = Column(Integer, ForeignKey("courses.id"), nullable=False)
    title = Column(String, nullable=False)
    description = Column(String)
    due_date = Column(DateTime)
    status = Column(String, default="open")
    is_completed = Column(Boolean, default=False)
    url = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    course = relationship("Course", back_populates="tasks")

class Credential(Base):
    __tablename__ = "credentials"
    
    id = Column(Integer, primary_key=True)
    moodle_url = Column(String, nullable=False)
    encrypted_username = Column(String, nullable=False)
    encrypted_password = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

engine = create_engine(f"sqlite:///{DB_PATH}", echo=False)
Base.metadata.create_all(engine)
SessionLocal = sessionmaker(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
