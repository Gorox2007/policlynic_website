from django.db import models
from django.core.exceptions import ValidationError
from django.utils import timezone


class WeekDay(models.TextChoices):
    MONDAY = '1', '1'
    TUESDAY = '2', '2'
    WEDNESDAY = '3', '3'
    THURSDAY = '4', '4'
    FRIDAY = '5', '5'
    SATURDAY = '6', '6'
    SUNDAY = '7', '7'

class Sex(models.TextChoices):
    MALE = 'm', 'm'
    FEMALE = 'f', 'f'

class Stat(models.TextChoices):
    SCHEDULED = 'scheduled', 'scheduled'
    COMPLETED = 'completed', 'completed'
    CANCELLED = 'cancelled', 'cancelled'

class Spec(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.TextField(unique=True)
    
    class Meta:
        db_table = 'spec'
        managed = False  # Таблица уже существует в БД
    
    def __str__(self):
        return self.name

class Doctor(models.Model):
    id = models.AutoField(primary_key=True)
    fname = models.TextField()
    lname = models.TextField()
    spec = models.ForeignKey(Spec, on_delete=models.DO_NOTHING, db_column='spec_id')
    phone = models.TextField(blank=True, null=True)
    is_available = models.BooleanField(default=True)
    
    class Meta:
        db_table = 'doctors'
        managed = False
    
    def __str__(self):
        return f"{self.lname} {self.fname}"

class Patient(models.Model):
    id = models.AutoField(primary_key=True)
    fname = models.TextField()
    lname = models.TextField()
    birth_date = models.DateField()
    gender = models.CharField(max_length=1, choices=Sex.choices)
    phone = models.TextField(blank=True, null=True)
    registered = models.DateField(default=timezone.now)
    
    class Meta:
        db_table = 'patients'
        managed = False
    
    def __str__(self):
        return f"{self.lname} {self.fname}"

class DocSchedule(models.Model):
    id = models.AutoField(primary_key=True)
    doctor = models.ForeignKey(Doctor, on_delete=models.CASCADE, db_column='doctor_id')
    day = models.CharField(max_length=1, choices=WeekDay.choices)
    start_time = models.TimeField()
    end_time = models.TimeField()
    
    class Meta:
        db_table = 'doc_schedule'
        managed = False
        unique_together = ('doctor_id', 'day')
    
    def __str__(self):
        return f"{self.doctor_id} - {self.day}: {self.start_time}-{self.end_time}"

class Diagnosis(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.TextField()
    
    class Meta:
        db_table = 'diagnoses'
        managed = False
    
    def __str__(self):
        return self.name

class Visit(models.Model):
    id = models.AutoField(primary_key=True)
    patient = models.ForeignKey(Patient, on_delete=models.CASCADE, db_column='patient_id')
    doctor = models.ForeignKey(Doctor, on_delete=models.CASCADE, db_column='doctor_id')
    visit_day = models.CharField(max_length=1, choices=WeekDay.choices)
    visit_date = models.DateField()
    visit_time = models.TimeField()
    diagnos = models.ForeignKey(Diagnosis, on_delete=models.SET_NULL, null=True, blank=True, db_column='diagnos_id')
    status = models.CharField(max_length=10, choices=Stat.choices, default=Stat.SCHEDULED)
    created = models.DateField(default=timezone.now)
    
    class Meta:
        db_table = 'visits'
        managed = False
        unique_together = ('doctor', 'visit_date', 'visit_time')
    
    def __str__(self):
        return f"Visit #{self.id}"
    
    def clean(self):

        errors = {}
        

        if self.visit_time.minute % 30 != 0:
            errors['visit_time'] = 'Время визита должно быть кратно 30 минутам.'
        

        if not self.doctor.is_available:
            errors['doctor'] = 'Доктор временно недоступен для записи'
        

        schedule_exists = DocSchedule.objects.filter(
            doctor=self.doctor,
            day=self.visit_day,
            start_time__lte=self.visit_time,
            end_time__gt=self.visit_time
        ).exists()
        
        if not schedule_exists:
            errors['visit_time'] = 'Доктор не работает в этот день или время'
        
        if errors:
            raise ValidationError(errors)

class Recipe(models.Model):
    id = models.AutoField(primary_key=True)
    visit = models.ForeignKey(Visit, on_delete=models.CASCADE, db_column='visit_id')
    drug = models.TextField()
    instructions = models.TextField(blank=True, null=True)
    
    class Meta:
        db_table = 'recipes'
        managed = False
    
    def __str__(self):
        return self.drug