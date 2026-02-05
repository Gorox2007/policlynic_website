from django.shortcuts import render, redirect, get_object_or_404
from django.http import HttpResponseForbidden
from django.db import connections
from .models import (
    Doctor,
    Patient,
    Visit,
    Diagnosis,
    Spec,
    DocSchedule
)

# =========================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# =========================

def is_operator(request):
    return request.session.get('is_operator', False)


def operator_required(view_func):
    def wrapper(request, *args, **kwargs):
        if not is_operator(request):
            return HttpResponseForbidden("Доступ только для оператора")
        return view_func(request, *args, **kwargs)
    return wrapper


# =========================
# ПЕРЕКЛЮЧЕНИЕ РЕЖИМА
# =========================

def enter_operator_mode(request):
    if request.method == 'POST':
        password = request.POST.get('password')

        # ТЕСТОВЫЙ ПАРОЛЬ
        if password == '123':
            request.session['is_operator'] = True
        else:
            request.session['operator_error'] = 'Неверный пароль'

    return redirect('home')


def exit_operator_mode(request):
    request.session['is_operator'] = False
    return redirect('home')


# =========================
# ГЛАВНАЯ
# =========================

def home(request):
    doctor_count = Doctor.objects.count()
    patient_count = Patient.objects.count()

    from django.utils import timezone
    today = timezone.now().date()
    today_visits = Visit.objects.filter(visit_date=today).count()

    recent_visits = Visit.objects.select_related(
        'patient', 'doctor', 'diagnos'
    ).order_by('-visit_date', '-visit_time')[:10]

    visits_list = []
    for visit in recent_visits:
        visits_list.append([
            visit.id,
            f"{visit.patient.fname} {visit.patient.lname}",
            f"{visit.doctor.fname} {visit.doctor.lname}",
            visit.visit_date,
            visit.visit_time,
            visit.diagnos.name if visit.diagnos else "Не указан",
            visit.status
        ])

    return render(request, 'polyclinic_app/index.html', {
        'doctor_count': doctor_count,
        'patient_count': patient_count,
        'today_visits': today_visits,
        'recent_visits': visits_list,
        'is_operator': is_operator(request),
        'operator_error': request.session.pop('operator_error', None),
    })



# =========================
# СПИСКИ (РАЗНЫЕ БД)
# =========================

def doctor_list(request):
    doctors = Doctor.objects.select_related('spec').all()

    doctors_data = []
    for doctor in doctors:
        doctors_data.append([
            doctor.id,
            doctor.fname,
            doctor.lname,
            doctor.spec.name if doctor.spec else "—",
            doctor.phone or "—",
            doctor.is_available
        ])

    return render(request, 'polyclinic_app/entity_list.html', {
        'entities': doctors_data,
        'title': 'Врачи',
        'columns': ['ID', 'Имя', 'Фамилия', 'Специальность', 'Телефон', 'Доступен'],
        'entity_name': 'doctors',
    })


def patient_list(request):
    patients = Patient.objects.all()

    patients_data = []
    for patient in patients:
        patients_data.append([
            patient.id,
            patient.fname,
            patient.lname,
            patient.birth_date,
            patient.gender,
            patient.phone or "—",
            patient.registered
        ])

    return render(request, 'polyclinic_app/entity_list.html', {
        'entities': patients_data,
        'title': 'Пациенты',
        'columns': [
            'ID',
            'Имя',
            'Фамилия',
            'Дата рождения',
            'Пол',
            'Телефон',
            'Зарегистрирован'
        ],
        'entity_name': 'patients',
    })



def visit_list(request):
    visits = Visit.objects.select_related('patient', 'doctor', 'diagnos') \
        .order_by('-visit_date', '-visit_time')

    visits_data = []
    for visit in visits:
        visits_data.append([
            visit.id,
            f"{visit.patient.lname} {visit.patient.fname}",
            f"{visit.doctor.lname} {visit.doctor.fname}",
            visit.visit_date,
            visit.visit_time.strftime("%H:%M"),
            visit.diagnos.name if visit.diagnos else "Не указан",
            visit.status
        ])

    return render(request, 'polyclinic_app/entity_list.html', {
        'entities': visits_data,
        'title': 'Визиты',
        'columns': [
            'ID',
            'Пациент',
            'Врач',
            'Дата',
            'Время',
            'Диагноз',
            'Статус'
        ],
        'entity_name': 'visits',
    })



def schedule_list(request):
    from django.db import connection

    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT 
                ds.doctor_id,
                ds.day,
                ds.start_time,
                ds.end_time,
                d.fname,
                d.lname,
                s.name
            FROM doc_schedule ds
            JOIN doctors d ON ds.doctor_id = d.id
            LEFT JOIN spec s ON d.spec_id = s.id
            ORDER BY d.lname, d.fname
        """)
        rows = cursor.fetchall()

    schedules_data = []
    for row in rows:
        schedules_data.append([
            f"{row[5]} {row[4]}",
            row[6] or "—",
            row[1],
            row[2].strftime("%H:%M") if row[2] else "—",
            row[3].strftime("%H:%M") if row[3] else "—",
        ])

    return render(request, 'polyclinic_app/entity_list.html', {
        'entities': schedules_data,
        'title': 'Расписание врачей',
        'columns': [
            'Врач',
            'Специальность',
            'День недели',
            'Начало',
            'Конец'
        ],
        'entity_name': 'schedules',
    })



# =========================
# ОПЕРАТОРСКИЕ ДЕЙСТВИЯ
# =========================

@operator_required
def visit_create(request):
    if request.method == 'POST':
        form = VisitForm(request.POST)
        if form.is_valid():
            visit = Visit(
                patient=form.cleaned_data['patient'],
                doctor=form.cleaned_data['doctor'],
                visit_date=form.cleaned_data['visit_date'],
                visit_time=form.cleaned_data['visit_time'],
                visit_day=form.cleaned_data['visit_day'],
                diagnos=form.cleaned_data['diagnos'],
                status=form.cleaned_data['status'],
            )

            try:
                visit.full_clean()  # Проверка всех условий модели
                visit.save()
                return redirect('visit_list')
            except Exception as e:
                form.add_error(None, e)

    else:
        form = VisitForm()

    return render(request, 'polyclinic_app/visit_create.html', {
        'form': form,
        'is_operator': is_operator(request),
    })



from django.shortcuts import render, redirect
from django.db import connections


from django.shortcuts import render, redirect, get_object_or_404
from django.contrib import messages
from .models import Visit, Doctor, Patient, Diagnosis
from .forms import VisitForm



@operator_required
def visit_edit(request, visit_id):
    visit = get_object_or_404(Visit, pk=visit_id)

    if request.method == 'POST':
        form = VisitForm(request.POST)
        if form.is_valid():
            # Обновляем поля модели вручную
            visit.patient = form.cleaned_data['patient']
            visit.doctor = form.cleaned_data['doctor']
            visit.visit_date = form.cleaned_data['visit_date']
            visit.visit_time = form.cleaned_data['visit_time']
            visit.visit_day = form.cleaned_data['visit_day']
            visit.diagnos = form.cleaned_data['diagnos']
            visit.status = form.cleaned_data['status']

            try:
                visit.full_clean()  # Вызов встроенных проверок clean()
                visit.save()
            except Exception as e:
                form.add_error(None, e)
                return render(request, 'polyclinic_app/visit_edit.html', {'form': form, 'visit': visit})

            return redirect('visit_list')
    else:
        # Инициализация формы текущими значениями визита
        form = VisitForm(initial={
            'patient': visit.patient,
            'doctor': visit.doctor,
            'visit_date': visit.visit_date,
            'visit_time': visit.visit_time,
            'visit_day': visit.visit_day,
            'diagnos': visit.diagnos,
            'status': visit.status,
        })

    return render(request, 'polyclinic_app/visit_edit.html', {
        'form': form,
        'visit': visit,
        'is_operator': is_operator(request),
    })




@operator_required
def visit_delete(request, visit_id):
    visit = get_object_or_404(Visit, pk=visit_id)
    try:
        visit.delete()
    except Exception as e:

        from django.contrib import messages
        messages.error(request, f"Ошибка при удалении визита: {e}")
    return redirect('visit_list')



from django.contrib import messages
from django.shortcuts import get_object_or_404

from django.utils import timezone
from django.contrib import messages

@operator_required
def cancel_patient_appointments(request):
    from .models import Patient, Visit

    # Список всех пациентов для выпадающего списка
    patients = Patient.objects.all().order_by('lname', 'fname')
    patients_list = [(p.id, f"{p.lname} {p.fname}") for p in patients]

    if request.method == 'POST':
        patient_id = request.POST.get('patient_id')
        if patient_id:
            patient = get_object_or_404(Patient, pk=patient_id)

            # Отбираем только будущие и запланированные визиты
            visits_to_cancel = Visit.objects.filter(
                patient=patient,
                status='scheduled',
            )

            count = visits_to_cancel.count()

            if count > 0:
                visits_to_cancel.update(status='cancelled')
                messages.success(request, f"Отменено {count} запланированных визитов пациента {patient}.")
            else:
                messages.info(request, f"У пациента {patient} нет запланированных визитов для отмены.")

            return redirect('cancel_appointments')

        else:
            messages.error(request, "Пожалуйста, выберите пациента для отмены визитов.")

    return render(request, 'polyclinic_app/cancel_appointments.html', {
        'patients': patients_list,
        'title': 'Отмена всех запланированных визитов',
        'is_operator': is_operator(request),
    })




# =========================
# ОТЧЁТЫ
# =========================

def report_doctor_stats(request):
    from django.db.models import Count, Q, Min, Max

    doctors = Doctor.objects.select_related('spec').annotate(
        total_visits=Count('visit'),
        completed_visits=Count('visit', filter=Q(visit__status='completed')),
        cancelled_visits=Count('visit', filter=Q(visit__status='cancelled')),
        scheduled_visits=Count('visit', filter=Q(visit__status='scheduled')),
        first_visit_date=Min('visit__visit_date'),
        last_visit_date=Max('visit__visit_date'),
    ).order_by('-total_visits')

    rows = []
    for d in doctors:
        rows.append([
            d.id,
            f"{d.lname} {d.fname}",
            d.spec.name if d.spec else "—",
            d.total_visits,
            d.completed_visits,
            d.scheduled_visits,
            d.cancelled_visits,
            d.first_visit_date or "—",
            d.last_visit_date or "—",
        ])

    return render(request, 'polyclinic_app/entity_list.html', {
        'title': 'Статистика врачей',
        'columns': [
            'ID',
            'Врач',
            'Специальность',
            'Всего визитов',
            'Завершено',
            'Запланировано',
            'Отменено',
            'Первый визит',
            'Последний визит',
        ],
        'entities': rows,
        'entity_name': 'doctor_stats',
    })



from django.db import connections

def report_next_visits(request):
    visits = None

    # список врачей для выпадающего списка
    with connections['client'].cursor() as cursor:
        cursor.execute("SELECT id, lname || ' ' || fname as full_name FROM doctors ORDER BY full_name")
        doctors = cursor.fetchall()

    if request.method == 'POST':
        doctor_id = request.POST.get('doctor_id')

        with connections['client'].cursor() as cursor:
            cursor.execute("""
                SELECT v.visit_date, p.lname || ' ' || p.fname as full_name
                FROM visits v
                JOIN patients p ON p.id = v.patient_id
                WHERE v.doctor_id = %s
                  AND v.visit_date >= CURRENT_DATE
                ORDER BY v.visit_date
            """, [doctor_id])
            visits = cursor.fetchall()

    return render(
        request,
        'polyclinic_app/report_next_visits_form.html',
        {
            'doctors': doctors,
            'visits': visits
        }
    )


