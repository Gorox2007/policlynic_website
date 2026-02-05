from django.urls import path
from . import views

urlpatterns = [
    # Главная
    path('', views.home, name='home'),

    # =====================
    # РЕЖИМ САЙТА
    # =====================
    path('operator/login/', views.enter_operator_mode, name='enter_operator'),
    path('operator/logout/', views.exit_operator_mode, name='exit_operator'),

    # =====================
    # СПРАВОЧНИКИ (ВСЕМ)
    # =====================
    path('doctors/', views.doctor_list, name='doctor_list'),
    path('patients/', views.patient_list, name='patient_list'),
    path('visits/', views.visit_list, name='visit_list'),
    path('schedules/', views.schedule_list, name='schedule_list'),

    # =====================
    # ОТЧЁТЫ (ВСЕМ)
    # =====================
    path('reports/doctor-stats/', views.report_doctor_stats, name='report_doctor_stats'),
    path('reports/next-visits/', views.report_next_visits, name='report_next_visits'),

    # =====================
    # ОПЕРАТОРСКИЕ ДЕЙСТВИЯ
    # =====================
    path('cancel-appointments/', views.cancel_patient_appointments, name='cancel_appointments'),

    path('visits/create/', views.visit_create, name='visit_create'),
    path('visits/edit/<int:visit_id>/', views.visit_edit, name='visit_edit'),
    path('visits/delete/<int:visit_id>/', views.visit_delete, name='visit_delete'),
]
