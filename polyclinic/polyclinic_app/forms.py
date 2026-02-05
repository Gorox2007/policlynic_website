from django import forms
from .models import Patient, Doctor, Diagnosis, Visit

class VisitForm(forms.Form):
    """Форма для создания/редактирования визита через ORM"""
    patient = forms.ModelChoiceField(
        label="Пациент",
        queryset=Patient.objects.all().order_by('lname', 'fname'),
        widget=forms.Select(attrs={'class': 'form-control'})
    )
    
    doctor = forms.ModelChoiceField(
        label="Врач",
        queryset=Doctor.objects.filter(is_available=True).order_by('lname', 'fname'),
        widget=forms.Select(attrs={'class': 'form-control'})
    )
    
    visit_date = forms.DateField(
        label="Дата", 
        widget=forms.DateInput(attrs={'type': 'date', 'class': 'form-control'})
    )
    
    visit_time = forms.TimeField(
        label="Время", 
        widget=forms.TimeInput(attrs={'type': 'time', 'class': 'form-control'})
    )
    
    visit_day = forms.ChoiceField(
        label="День недели", 
        choices=Visit._meta.get_field('visit_day').choices,
        widget=forms.Select(attrs={'class': 'form-control'})
    )
    
    diagnos = forms.ModelChoiceField(
        label="Диагноз",
        queryset=Diagnosis.objects.all().order_by('name'),
        required=False,
        empty_label="--- Не выбран ---",
        widget=forms.Select(attrs={'class': 'form-control'})
    )
    
    status = forms.ChoiceField(
        label="Статус", 
        choices=Visit._meta.get_field('status').choices,
        widget=forms.Select(attrs={'class': 'form-control'})
    )