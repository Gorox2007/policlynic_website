create database polyclinic_db;


create type week_day as enum('1', '2', '3', '4', '5', '6', '7');
create type sex as enum('m', 'f');
create type stat as enum('scheduled', 'completed', 'cancelled');

create table spec (
    id serial primary key,
    name text not null unique
);

create table doctors (
    id serial primary key,
	fname text not null,
    lname text not null,
    spec_id int not null references spec(id),
    phone text
);
ALTER TABLE doctors ADD COLUMN is_available BOOLEAN DEFAULT TRUE;

create table patients (
    id serial primary key,
	fname text not null,
    lname text not null,
    birth_date date not null,
    gender sex,
    phone text,
    registered date default now()::date
);

create table doc_schedule (
    doctor_id int not null references doctors(id),
    day week_day,
    start_time time not null,
    end_time time not null,
    primary key (doctor_id, day)
);

create table diagnoses (
    id serial primary key,
    name text not null
);

create table visits (
    id serial primary key,
    patient_id int not null references patients(id),
    doctor_id int not null references doctors(id),
	visit_day week_day,
    visit_date date not null,
    visit_time time not null,
    diagnos_id int references diagnoses(id),
    status stat default 'scheduled',
    created date default now()::date,
    unique(doctor_id, visit_date, visit_time)
);

create table recipes (
    id serial primary key,
    visit_id int not null references visits(id),
    drug text not null,
    instructions text
);


CREATE OR REPLACE FUNCTION validate_visit()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXTRACT(MINUTE FROM NEW.visit_time) % 30 != 0 THEN
        RAISE EXCEPTION 'Время визита должно быть кратно 30 минутам.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM doctors 
        WHERE id = NEW.doctor_id 
        AND is_available = TRUE
    ) THEN
        RAISE EXCEPTION 'Доктор временно недоступен для записи';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM doc_schedule 
        WHERE doctor_id = NEW.doctor_id 
        AND day = NEW.visit_day
        AND start_time <= NEW.visit_time 
        AND NEW.visit_time < end_time
    ) THEN
        RAISE EXCEPTION 'Доктор не работает в этот день или время';
    END IF;

    RETURN NEW;
END
$$;



CREATE TRIGGER check_visit_constraints
BEFORE INSERT OR UPDATE ON visits
FOR EACH ROW
EXECUTE FUNCTION validate_visit();




CREATE OR REPLACE VIEW doctor_stats AS
SELECT 
    d.id AS doctor_id,
    d.fname || ' ' || d.lname AS doctor_name,
    s.name AS specialization,
    COUNT(v.id) AS total_visits,
    COUNT(CASE WHEN v.status = 'completed' THEN 1 END) AS completed_visits,
    COUNT(CASE WHEN v.status = 'cancelled' THEN 1 END) AS cancelled_visits,
    COUNT(CASE WHEN v.status = 'scheduled' THEN 1 END) AS scheduled_visits,
    MIN(v.visit_date) AS first_visit_date,
    MAX(v.visit_date) AS last_visit_date
FROM doctors d
JOIN spec s ON d.spec_id = s.id
LEFT JOIN visits v ON d.id = v.doctor_id
GROUP BY d.id, d.fname, d.lname, s.name
ORDER BY total_visits DESC;






CREATE OR REPLACE PROCEDURE cancel_all_patient_appointments(
    p_patient_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_patient_name TEXT;
BEGIN
    
    SELECT fname || ' ' || lname INTO v_patient_name
    FROM patients WHERE id = p_patient_id;
    
    IF v_patient_name IS NULL THEN
        RAISE EXCEPTION 'Пациент с ID % не найден', p_patient_id;
    END IF;
    
    UPDATE visits 
    SET status = 'cancelled'
    WHERE patient_id = p_patient_id
    AND status = 'scheduled'
    AND visit_date >= CURRENT_DATE;
    
    RAISE NOTICE 'Отменены все записи пациента: % (ID: %).', v_patient_name, p_patient_id;

END;
$$;


CREATE OR REPLACE PROCEDURE cancel_doctor_appointments(
    p_doctor_id INT,
    p_start_date DATE,
    p_end_date DATE
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM doctors WHERE id = p_doctor_id) THEN
        RAISE EXCEPTION 'Врач с ID % не найден', p_doctor_id;
    END IF;
    
    UPDATE visits 
    SET status = 'cancelled'::stat
    WHERE doctor_id = p_doctor_id
    AND visit_date BETWEEN p_start_date AND p_end_date
    AND status = 'scheduled'::stat;
    
    RAISE NOTICE 'Отменены записи врача ID: % с % по %', 
                 p_doctor_id, p_start_date, p_end_date;
END;
$$;


CREATE OR REPLACE FUNCTION next_doc_visits(
    p_doctor_id INT
)
RETURNS TABLE (
    appointment_date DATE,
    appointment_day TEXT,
    appointment_time TIME,
    patient_name TEXT,
    patient_phone TEXT,
    status TEXT
) 
LANGUAGE plpgsql
AS $$
BEGIN

    
    IF NOT EXISTS(SELECT 1 FROM doctors WHERE id = p_doctor_id) THEN
        RAISE EXCEPTION 'Врач с ID % не найден', p_doctor_id;
    END IF;

    RETURN QUERY
    SELECT 
        v.visit_date AS appointment_date,
        CASE 
            WHEN EXTRACT(ISODOW FROM v.visit_date) = 1 THEN 'Понедельник'
            WHEN EXTRACT(ISODOW FROM v.visit_date) = 2 THEN 'Вторник'
            WHEN EXTRACT(ISODOW FROM v.visit_date) = 3 THEN 'Среда'
            WHEN EXTRACT(ISODOW FROM v.visit_date) = 4 THEN 'Четверг'
            WHEN EXTRACT(ISODOW FROM v.visit_date) = 5 THEN 'Пятница'
            WHEN EXTRACT(ISODOW FROM v.visit_date) = 6 THEN 'Суббота'
            WHEN EXTRACT(ISODOW FROM v.visit_date) = 7 THEN 'Воскресенье'
        END AS appointment_day,
        v.visit_time AS appointment_time,
        p.fname || ' ' || p.lname AS patient_name,
        p.phone AS patient_phone,
        v.status::TEXT AS status
    FROM visits v
    JOIN patients p ON v.patient_id = p.id
    WHERE v.doctor_id = p_doctor_id
    AND v.visit_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 6
    AND v.status = 'scheduled'
    ORDER BY v.visit_date, v.visit_time;
    

    IF NOT FOUND THEN
        RAISE NOTICE 'У врача с ID % нет запланированных визитов на ближайшие 7 дней', p_doctor_id;
    END IF;
END;
$$;


CREATE TABLE doctors_history (
    history_id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL CHECK (operation_type IN ('I', 'U', 'D')), -- I=Insert, U=Update, D=Delete
    operation_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    operation_user TEXT DEFAULT CURRENT_USER,
    
    id INT NOT NULL,
    fname TEXT NOT NULL,
    lname TEXT NOT NULL,
    spec_id INT NOT NULL,
    phone TEXT,
    is_available BOOLEAN DEFAULT TRUE,
    

    current_record_id INT REFERENCES doctors(id) ON DELETE SET NULL
);


CREATE TABLE patients_history (
    history_id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL CHECK (operation_type IN ('I', 'U', 'D')),
    operation_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    operation_user TEXT DEFAULT CURRENT_USER,
    

    id INT NOT NULL,
    fname TEXT NOT NULL,
    lname TEXT NOT NULL,
    birth_date DATE NOT NULL,
    gender sex,
    phone TEXT,
    registered DATE DEFAULT CURRENT_DATE,
    
    current_record_id INT REFERENCES patients(id) ON DELETE SET NULL
);


CREATE TABLE visits_history (
    history_id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL CHECK (operation_type IN ('I', 'U', 'D')),
    operation_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    operation_user TEXT DEFAULT CURRENT_USER,


    id INT NOT NULL,
    patient_id INT NOT NULL,
    doctor_id INT NOT NULL,
    visit_day week_day,
    visit_date DATE NOT NULL,
    visit_time TIME NOT NULL,
    diagnos_id INT,
    status stat DEFAULT 'scheduled',
    created DATE DEFAULT CURRENT_DATE,
    
    current_record_id INT REFERENCES visits(id) ON DELETE SET NULL
);


CREATE OR REPLACE FUNCTION save_full_history()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_history_table TEXT;
    v_sql TEXT;
BEGIN
    v_history_table := TG_TABLE_NAME || '_history';
    
    IF TG_OP = 'INSERT' THEN
        v_sql := 'INSERT INTO ' || quote_ident(v_history_table) || 
                 ' (operation_type, id, fname, lname';
        
        IF TG_TABLE_NAME = 'doctors' THEN
            v_sql := v_sql || ', spec_id, phone, is_available, current_record_id) ' ||
                     'VALUES (''I'', $1.id, $1.fname, $1.lname, ' ||
                     '$1.spec_id, $1.phone, $1.is_available, $1.id)';
            EXECUTE v_sql USING NEW;
            
        ELSIF TG_TABLE_NAME = 'patients' THEN
            v_sql := v_sql || ', birth_date, gender, phone, registered, current_record_id) ' ||
                     'VALUES (''I'', $1.id, $1.fname, $1.lname, ' ||
                     '$1.birth_date, $1.gender, $1.phone, $1.registered, $1.id)';
            EXECUTE v_sql USING NEW;
            
        ELSIF TG_TABLE_NAME = 'visits' THEN
            v_sql := 'INSERT INTO ' || quote_ident(v_history_table) || 
                     ' (operation_type, id, patient_id, doctor_id, visit_day, ' ||
                     'visit_date, visit_time, diagnos_id, status, created, current_record_id) ' ||
                     'VALUES (''I'', $1.id, $1.patient_id, $1.doctor_id, $1.visit_day, ' ||
                     '$1.visit_date, $1.visit_time, $1.diagnos_id, $1.status, $1.created, $1.id)';
            EXECUTE v_sql USING NEW;
        END IF;
        
    ELSIF TG_OP = 'UPDATE' THEN
        v_sql := 'INSERT INTO ' || quote_ident(v_history_table) || 
                 ' (operation_type, id, fname, lname';
        
        IF TG_TABLE_NAME = 'doctors' THEN
            v_sql := v_sql || ', spec_id, phone, is_available, current_record_id) ' ||
                     'VALUES (''U'', $1.id, $1.fname, $1.lname, ' ||
                     '$1.spec_id, $1.phone, $1.is_available, $1.id)';
            EXECUTE v_sql USING OLD;
            
        ELSIF TG_TABLE_NAME = 'patients' THEN
            v_sql := v_sql || ', birth_date, gender, phone, registered, current_record_id) ' ||
                     'VALUES (''U'', $1.id, $1.fname, $1.lname, ' ||
                     '$1.birth_date, $1.gender, $1.phone, $1.registered, $1.id)';
            EXECUTE v_sql USING OLD;
            
        ELSIF TG_TABLE_NAME = 'visits' THEN
            v_sql := 'INSERT INTO ' || quote_ident(v_history_table) || 
                     ' (operation_type, id, patient_id, doctor_id, visit_day, ' ||
                     'visit_date, visit_time, diagnos_id, status, created, current_record_id) ' ||
                     'VALUES (''U'', $1.id, $1.patient_id, $1.doctor_id, $1.visit_day, ' ||
                     '$1.visit_date, $1.visit_time, $1.diagnos_id, $1.status, $1.created, $1.id)';
            EXECUTE v_sql USING OLD;
        END IF;
        
    ELSIF TG_OP = 'DELETE' THEN
        v_sql := 'INSERT INTO ' || quote_ident(v_history_table) || 
                 ' (operation_type, id, fname, lname';
        
        IF TG_TABLE_NAME = 'doctors' THEN
            v_sql := v_sql || ', spec_id, phone, is_available, current_record_id) ' ||
                     'VALUES (''D'', $1.id, $1.fname, $1.lname, ' ||
                     '$1.spec_id, $1.phone, $1.is_available, NULL)';
            EXECUTE v_sql USING OLD;
            
        ELSIF TG_TABLE_NAME = 'patients' THEN
            v_sql := v_sql || ', birth_date, gender, phone, registered, current_record_id) ' ||
                     'VALUES (''D'', $1.id, $1.fname, $1.lname, ' ||
                     '$1.birth_date, $1.gender, $1.phone, $1.registered, NULL)';
            EXECUTE v_sql USING OLD;
            
        ELSIF TG_TABLE_NAME = 'visits' THEN
            v_sql := 'INSERT INTO ' || quote_ident(v_history_table) || 
                     ' (operation_type, id, patient_id, doctor_id, visit_day, ' ||
                     'visit_date, visit_time, diagnos_id, status, created, current_record_id) ' ||
                     'VALUES (''D'', $1.id, $1.patient_id, $1.doctor_id, $1.visit_day, ' ||
                     '$1.visit_date, $1.visit_time, $1.diagnos_id, $1.status, $1.created, NULL)';
            EXECUTE v_sql USING OLD;
        END IF;
    END IF;
    
    RETURN NULL; 
END;
$$;


-- Триггер для врачей
CREATE TRIGGER doctors_history_trigger
AFTER INSERT OR UPDATE OR DELETE ON doctors
FOR EACH ROW
EXECUTE FUNCTION save_full_history();

-- Триггер для пациентов
CREATE TRIGGER patients_history_trigger
AFTER INSERT OR UPDATE OR DELETE ON patients
FOR EACH ROW
EXECUTE FUNCTION save_full_history();

-- Триггер для визитов
CREATE TRIGGER visits_history_trigger
AFTER INSERT OR UPDATE OR DELETE ON visits
FOR EACH ROW
EXECUTE FUNCTION save_full_history();








CREATE ROLE polyclinic_admin WITH LOGIN PASSWORD 'admin123';    -- Администратор
CREATE ROLE polyclinic_operator WITH LOGIN PASSWORD 'oper123'; -- Оператор  
CREATE ROLE polyclinic_client WITH LOGIN PASSWORD 'client123';   -- Клиент (только чтение)


GRANT CONNECT ON DATABASE polyclinic_db TO 
    polyclinic_admin, 
    polyclinic_operator, 
    polyclinic_client;


GRANT USAGE ON SCHEMA public TO 
    polyclinic_admin, 
    polyclinic_operator, 
    polyclinic_client;


GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO polyclinic_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO polyclinic_admin;


GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO polyclinic_operator;


GRANT SELECT ON 
    doctors,
    patients, 
    visits,
    spec,
    diagnoses,
    doc_schedule
TO polyclinic_client;






















-- Вставляем специальности врачей
INSERT INTO spec (name) VALUES
('Терапевт'),
('Хирург'),
('Невролог'),
('Кардиолог'),
('Отоларинголог (ЛОР)'),
('Офтальмолог'),
('Гинеколог'),
('Уролог'),
('Дерматолог'),
('Педиатр'),
('Стоматолог'),
('Травматолог'),
('Эндокринолог'),
('Гастроэнтеролог'),
('Психиатр');

-- Вставляем врачей
INSERT INTO doctors (fname, lname, spec_id, phone, is_available) VALUES
('Иван', 'Иванов', 1, '+79991234567', TRUE),
('Петр', 'Петров', 2, '+79992345678', TRUE),
('Мария', 'Сидорова', 3, '+79993456789', TRUE),
('Анна', 'Кузнецова', 4, '+79994567890', TRUE),
('Сергей', 'Смирнов', 5, '+79995678901', TRUE),
('Ольга', 'Попова', 6, '+79996789012', TRUE),
('Алексей', 'Васильев', 7, '+79997890123', FALSE), -- временно недоступен
('Елена', 'Морозова', 8, '+79998901234', TRUE),
('Дмитрий', 'Новиков', 9, '+79999012345', TRUE),
('Наталья', 'Федорова', 10, '+79990123456', TRUE),
('Андрей', 'Павлов', 11, '+79991234560', TRUE),
('Татьяна', 'Козлова', 12, '+79992345670', TRUE),
('Владимир', 'Лебедев', 13, '+79993456780', TRUE),
('Светлана', 'Соколова', 14, '+79994567890', TRUE),
('Михаил', 'Кузнецов', 15, '+79995678900', TRUE);

-- Вставляем пациентов (30 пациентов)
INSERT INTO patients (fname, lname, birth_date, gender, phone, registered) VALUES
('Александр', 'Соколов', '1985-03-15', 'm', '+79161112233', '2024-01-10'),
('Екатерина', 'Волкова', '1990-07-22', 'f', '+79162223344', '2024-01-12'),
('Михаил', 'Зайцев', '1978-11-30', 'm', '+79163334455', '2024-01-15'),
('Анна', 'Павлова', '1995-02-14', 'f', '+79164445566', '2024-01-20'),
('Владимир', 'Семенов', '1982-09-05', 'm', '+79165556677', '2024-01-25'),
('Ирина', 'Голубева', '1988-12-18', 'f', '+79166667788', '2024-02-01'),
('Андрей', 'Виноградов', '1975-06-25', 'm', '+79167778899', '2024-02-05'),
('Татьяна', 'Белова', '1992-04-08', 'f', '+79168889900', '2024-02-10'),
('Павел', 'Комаров', '1980-08-12', 'm', '+79169990011', '2024-02-15'),
('Юлия', 'Орлова', '1998-01-28', 'f', '+79160001122', '2024-02-20'),
('Николай', 'Антонов', '1965-05-17', 'm', '+79161113344', '2024-02-25'),
('Светлана', 'Титова', '1972-10-03', 'f', '+79162224455', '2024-03-01'),
('Артем', 'Крылов', '1993-03-19', 'm', '+79163335566', '2024-03-05'),
('Марина', 'Лебедева', '1987-07-07', 'f', '+79164446677', '2024-03-10'),
('Константин', 'Соловьев', '1970-11-11', 'm', '+79165557788', '2024-03-15'),
('Ольга', 'Васильева', '1983-04-25', 'f', '+79166668899', '2024-03-20'),
('Денис', 'Зайцев', '1991-08-30', 'm', '+79167779900', '2024-03-25'),
('Евгения', 'Петрова', '1989-12-05', 'f', '+79168880011', '2024-04-01'),
('Роман', 'Федоров', '1977-06-18', 'm', '+79169991122', '2024-04-05'),
('Алина', 'Морозова', '1996-09-22', 'f', '+79160002233', '2024-04-10'),
('Георгий', 'Алексеев', '1968-02-14', 'm', '+79161114455', '2024-04-15'),
('Людмила', 'Степанова', '1974-05-28', 'f', '+79162225566', '2024-04-20'),
('Вадим', 'Егоров', '1984-10-11', 'm', '+79163336677', '2024-04-25'),
('Виктория', 'Ковалева', '1994-01-24', 'f', '+79164447788', '2024-05-01'),
('Станислав', 'Ильин', '1979-07-07', 'm', '+79165558899', '2024-05-05'),
('Ксения', 'Гаврилова', '1986-03-19', 'f', '+79166669900', '2024-05-10'),
('Игорь', 'Тихонов', '1973-11-02', 'm', '+79167770011', '2024-05-15'),
('Валерия', 'Кузьмина', '1997-06-15', 'f', '+79168881122', '2024-05-20'),
('Григорий', 'Поляков', '1969-09-28', 'm', '+79169992233', '2024-05-25'),
('Диана', 'Власова', '1981-12-10', 'f', '+79160003344', '2024-05-30');

-- Вставляем диагнозы
INSERT INTO diagnoses (name) VALUES
('ОРВИ'),
('Грипп'),
('Гипертоническая болезнь'),
('Остеохондроз'),
('Гастрит'),
('Бронхит'),
('Ангина'),
('Сахарный диабет'),
('Аллергический ринит'),
('Конъюнктивит'),
('Цистит'),
('Дерматит'),
('Мигрень'),
('Артрит'),
('Пневмония'),
('Язвенная болезнь'),
('Холецистит'),
('Панкреатит'),
('Гепатит'),
('Нефрит'),
('Пиелонефрит'),
('Бронхиальная астма'),
('Ишемическая болезнь сердца'),
('Вегетососудистая дистония'),
('Депрессия'),
('Тревожное расстройство'),
('Кариес'),
('Пародонтит'),
('Перелом'),
('Растяжение связок');

-- Вставляем расписание врачей
INSERT INTO doc_schedule (doctor_id, day, start_time, end_time) VALUES
-- Врач 1 (Иванов) - терапевт, пн-пт
(1, '1', '09:00', '18:00'),
(1, '2', '09:00', '18:00'),
(1, '3', '09:00', '18:00'),
(1, '4', '09:00', '18:00'),
(1, '5', '09:00', '16:00'),

-- Врач 2 (Петров) - хирург, вт-сб
(2, '2', '08:00', '17:00'),
(2, '3', '08:00', '17:00'),
(2, '4', '08:00', '17:00'),
(2, '5', '08:00', '17:00'),
(2, '6', '10:00', '15:00'),

-- Врач 3 (Сидорова) - невролог, пн, ср, пт
(3, '1', '10:00', '19:00'),
(3, '3', '10:00', '19:00'),
(3, '5', '10:00', '19:00'),

-- Врач 4 (Кузнецова) - кардиолог, все дни кроме воскресенья
(4, '1', '08:30', '16:30'),
(4, '2', '08:30', '16:30'),
(4, '3', '08:30', '16:30'),
(4, '4', '08:30', '16:30'),
(4, '5', '08:30', '16:30'),
(4, '6', '09:00', '14:00'),

-- Врач 5 (Смирнов) - ЛОР, пн-чт
(5, '1', '11:00', '20:00'),
(5, '2', '11:00', '20:00'),
(5, '3', '11:00', '20:00'),
(5, '4', '11:00', '20:00'),

-- Врач 6 (Попова) - офтальмолог, вт, чт, сб
(6, '2', '09:30', '18:30'),
(6, '4', '09:30', '18:30'),
(6, '6', '10:00', '16:00'),

-- Врач 7 (Васильев) - гинеколог, вт, чт (недоступен)
(7, '2', '12:00', '21:00'),
(7, '4', '12:00', '21:00'),

-- Врач 8 (Морозова) - уролог, пн-пт
(8, '1', '08:00', '17:00'),
(8, '2', '08:00', '17:00'),
(8, '3', '08:00', '17:00'),
(8, '4', '08:00', '17:00'),
(8, '5', '08:00', '15:00'),

-- Врач 9 (Новиков) - дерматолог, ср, пт, сб
(9, '3', '13:00', '22:00'),
(9, '5', '13:00', '22:00'),
(9, '6', '11:00', '18:00'),

-- Врач 10 (Федорова) - педиатр, пн, ср, чт
(10, '1', '07:30', '16:30'),
(10, '3', '07:30', '16:30'),
(10, '4', '07:30', '16:30'),

-- Врач 11 (Павлов) - стоматолог, пн-сб
(11, '1', '08:00', '20:00'),
(11, '2', '08:00', '20:00'),
(11, '3', '08:00', '20:00'),
(11, '4', '08:00', '20:00'),
(11, '5', '08:00', '20:00'),
(11, '6', '09:00', '17:00'),

-- Врач 12 (Козлова) - травматолог, пн, вт, чт, пт
(12, '1', '09:00', '18:00'),
(12, '2', '09:00', '18:00'),
(12, '4', '09:00', '18:00'),
(12, '5', '09:00', '18:00'),

-- Врач 13 (Лебедев) - эндокринолог, вт-сб
(13, '2', '10:00', '19:00'),
(13, '3', '10:00', '19:00'),
(13, '4', '10:00', '19:00'),
(13, '5', '10:00', '19:00'),
(13, '6', '10:00', '16:00'),

-- Врач 14 (Соколова) - гастроэнтеролог, пн, ср, пт
(14, '1', '08:30', '17:30'),
(14, '3', '08:30', '17:30'),
(14, '5', '08:30', '17:30'),

-- Врач 15 (Кузнецов) - психиатр, вт, чт
(15, '2', '14:00', '22:00'),
(15, '4', '14:00', '22:00');

-- Вставляем валидные визиты с учетом расписания врачей
-- Для каждого визита: дата, когда врач работает, и время в его рабочем интервале

INSERT INTO visits (patient_id, doctor_id, visit_date, visit_time, visit_day, diagnos_id, status) 
VALUES 
         (11, 1, CURRENT_DATE + 3, '09:30'::time, '4'::week_day, 11, 'scheduled'::stat),
    (12, 1, CURRENT_DATE + 3, '11:00'::time, '4'::week_day, 12, 'scheduled'::stat),
    
    -- Врач 5 (Смирнов) - ЛОР, работает в четверг 11:00-20:00
    (13, 5, CURRENT_DATE + 3, '12:30'::time, '4'::week_day, 13, 'scheduled'::stat),
    (14, 5, CURRENT_DATE + 3, '16:00'::time, '4'::week_day, 14, 'scheduled'::stat),
    
    -- Врач 6 (Попова) - офтальмолог, работает в четверг 09:30-18:30
    (15, 6, CURRENT_DATE + 3, '10:30'::time, '4'::week_day, 15, 'scheduled'::stat),
    (16, 6, CURRENT_DATE + 3, '14:00'::time, '4'::week_day, 16, 'scheduled'::stat),
    
    -- Врач 8 (Морозова) - уролог, работает в четверг 08:00-17:00
    (17, 8, CURRENT_DATE + 3, '08:30'::time, '4'::week_day, 17, 'scheduled'::stat),
    (18, 8, CURRENT_DATE + 3, '13:30'::time, '4'::week_day, 18, 'scheduled'::stat),
    
    -- Врач 15 (Кузнецов) - психиатр, работает в четверг 14:00-22:00
    (19, 15, CURRENT_DATE + 3, '15:30'::time, '4'::week_day, 19, 'scheduled'::stat),
    (20, 15, CURRENT_DATE + 3, '19:00'::time, '4'::week_day, 20, 'scheduled'::stat),
    
    -- ========== СРЕДА (день '3') ==========
    -- Предположим, что через 2 дня среда (current_date + 2 = среда)
    -- Врач 3 (Сидорова) - невролог, работает в среду 10:00-19:00
    (21, 3, CURRENT_DATE + 2, '11:00'::time, '3'::week_day, 21, 'scheduled'::stat),
    (22, 3, CURRENT_DATE + 2, '14:30'::time, '3'::week_day, 22, 'scheduled'::stat),
    
    -- Врач 9 (Новиков) - дерматолог, работает в среду 13:00-22:00
    (23, 9, CURRENT_DATE + 2, '14:00'::time, '3'::week_day, 23, 'scheduled'::stat),
    (24, 9, CURRENT_DATE + 2, '17:30'::time, '3'::week_day, 24, 'scheduled'::stat),
    
    -- Врач 14 (Соколова) - гастроэнтеролог, работает в среду 08:30-17:30
    (25, 14, CURRENT_DATE + 2, '10:00'::time, '3'::week_day, 25, 'scheduled'::stat),
    (26, 14, CURRENT_DATE + 2, '15:00'::time, '3'::week_day, 26, 'scheduled'::stat),
    
    -- ========== ПЯТНИЦА (день '5') ==========
    -- Предположим, что через 4 дня пятница (current_date + 4 = пятница)
    -- Врач 1 (Иванов) - терапевт, работает в пятницу 09:00-16:00
    (27, 1, CURRENT_DATE + 4, '10:30'::time, '5'::week_day, 27, 'scheduled'::stat),
    (28, 1, CURRENT_DATE + 4, '13:00'::time, '5'::week_day, 28, 'scheduled'::stat),
    
    -- Врач 3 (Сидорова) - невролог, работает в пятницу 10:00-19:00
    (29, 3, CURRENT_DATE + 4, '12:00'::time, '5'::week_day, 29, 'scheduled'::stat),
    (30, 3, CURRENT_DATE + 4, '16:30'::time, '5'::week_day, 30, 'scheduled'::stat),
    
    -- Врач 9 (Новиков) - дерматолог, работает в пятницу 13:00-22:00
    (1, 9, CURRENT_DATE + 4, '14:30'::time, '5'::week_day, 1, 'scheduled'::stat),
    (2, 9, CURRENT_DATE + 4, '18:00'::time, '5'::week_day, 2, 'scheduled'::stat),
    
    -- ========== СУББОТА (день '6') ==========
    -- Предположим, что через 5 дней суббота (current_date + 5 = суббота)
    -- Врач 2 (Петров) - хирург, работает в субботу 10:00-15:00
    (3, 2, CURRENT_DATE + 5, '11:00'::time, '6'::week_day, 3, 'scheduled'::stat),
    (4, 2, CURRENT_DATE + 5, '13:30'::time, '6'::week_day, 4, 'scheduled'::stat),
    
    -- Врач 6 (Попова) - офтальмолог, работает в субботу 10:00-16:00
    (5, 6, CURRENT_DATE + 5, '11:30'::time, '6'::week_day, 5, 'scheduled'::stat),
    (6, 6, CURRENT_DATE + 5, '14:00'::time, '6'::week_day, 6, 'scheduled'::stat),
    
    -- ========== ПОНЕДЕЛЬНИК (день '1') ==========
    -- Предположим, что через 7 дней понедельник (current_date + 7 = понедельник)
    -- Врач 3 (Сидорова) - невролог, работает в понедельник 10:00-19:00
    (7, 3, CURRENT_DATE + 7, '12:00'::time, '1'::week_day, 7, 'scheduled'::stat),
    (8, 3, CURRENT_DATE + 7, '16:00'::time, '1'::week_day, 8, 'scheduled'::stat),
    
    -- Врач 8 (Морозова) - уролог, работает в понедельник 08:00-17:00
    (9, 8, CURRENT_DATE + 7, '09:00'::time, '1'::week_day, 9, 'scheduled'::stat),
    (10, 8, CURRENT_DATE + 7, '14:30'::time, '1'::week_day, 10, 'scheduled'::stat);

-- Вставляем рецепты для завершенных визитов
INSERT INTO recipes (visit_id, drug, instructions) VALUES
(81, 'Парацетамол', 'По 1 таблетке 3 раза в день после еды'),
(81, 'Аскорбиновая кислота', 'По 1 драже 2 раза в день'),
(82, 'Эналаприл', 'По 5 мг утром натощак'),
(83, 'Диклофенак', 'Мазь, наносить на болезненные участки 2 раза в день'),
(84, 'Осельтамивир', 'По 75 мг 2 раза в день в течение 5 дней'),
(85, 'Омепразол', 'По 20 мг утром за 30 минут до еды'),
(86, 'Амоксициллин', 'По 500 мг 3 раза в день в течение 7 дней'),
(87, 'Азитромицин', 'По 500 мг 1 раз в день в течение 3 дней'),
(88, 'Метформин', 'По 500 мг 2 раза в день во время еды'),
(89, 'Лоратадин', 'По 1 таблетке 1 раз в день'),
(90, 'Альбуцид', 'По 1-2 капли в каждый глаз 3-4 раза в день'),
(91, 'Но-шпа', 'По 1 таблетке 3 раза в день при болях'),
(92, 'Нурофен', 'По 200 мг 3 раза в день после еды'),
(93, 'Валерьянка', 'По 30 капель 3 раза в день'),
(94, 'Глицин', 'По 1 таблетке 3 раза в день под язык'),
(95, 'Активированный уголь', 'По 2 таблетки 3 раза в день'),
(96, 'Линекс', 'По 2 капсулы 3 раза в день'),
(97, 'Смекта', 'По 1 пакетику 3 раза в день'),
(98, 'Анальгин', 'По 1 таблетке при сильных болях'),
(99, 'Цитрамон', 'По 1 таблетке при головной боли'),
(100, 'Валокордин', 'По 20 капель при беспокойстве'),
(101, 'Кагоцел', 'По схеме: 2 дня по 2 таблетки, затем по 1 таблетке'),
(102, 'Арбидол', 'По 200 мг 4 раза в день'),
(103, 'Ингавирин', 'По 90 мг 1 раз в день'),
(104, 'Терафлю', 'По 1 пакетику 2-3 раза в день'),
(105, 'Ринза', 'По 1 таблетке 3-4 раза в день'),
(106, 'Стрепсилс', 'Рассасывать по 1 таблетке каждые 2-3 часа'),
(107, 'Фарингосепт', 'По 1 таблетке 3-5 раз в день'),
(108, 'Гексорал', 'Полоскать горло 2 раза в день'),
(109, 'Тантум Верде', 'По 1 дозе 3 раза в день'),
(100, 'Мирамистин', 'Орошать горло 3-4 раза в день');