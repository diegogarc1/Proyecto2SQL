-- Crear base de datos
CREATE DATABASE IF NOT EXISTS ProyectoDos;
USE ProyectoDos;

-- Tabla clientes
CREATE TABLE clientes (
    id_cliente INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    direccion VARCHAR(255),
    telefono VARCHAR(20) UNIQUE,
    email VARCHAR(100) UNIQUE,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_clientes_email ON clientes (email);

-- Tabla clientesMetadatos
CREATE TABLE clientesMetadatos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    cliente_id INT NOT NULL,
    creadoEn DATETIME NOT NULL,
    creadoPor INT NOT NULL,
    actualizadoEn DATETIME NOT NULL,
    actualizadoPor INT NOT NULL,
    archivado BOOLEAN NOT NULL,
    archivadoEn DATETIME,
    archivadoPor INT,
    FOREIGN KEY (cliente_id) REFERENCES clientes(id_cliente) ON DELETE CASCADE,
    FOREIGN KEY (creadoPor) REFERENCES clientes(id_cliente),
    FOREIGN KEY (actualizadoPor) REFERENCES clientes(id_cliente),
    FOREIGN KEY (archivadoPor) REFERENCES clientes(id_cliente) ON DELETE SET NULL
);

-- Tabla deudas
CREATE TABLE deudas (
    id_deuda INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    monto_original DECIMAL(10,2) NOT NULL,
    monto_pendiente DECIMAL(10,2) NOT NULL,
    fecha_vencimiento DATE NOT NULL,
    tipo_deuda VARCHAR(50),
    tasa_interes DECIMAL(5,2),
    fecha_inicio DATE,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE CASCADE
);

-- Tabla pagos
CREATE TABLE pagos (
    id_pago INT AUTO_INCREMENT PRIMARY KEY,
    id_deuda INT NOT NULL,
    fecha_pago DATE NOT NULL,
    monto_pagado DECIMAL(10,2) NOT NULL,
    metodo_pago VARCHAR(50),
    referencia VARCHAR(100),
    FOREIGN KEY (id_deuda) REFERENCES deudas(id_deuda) ON DELETE CASCADE
);

-- Tabla agentes
CREATE TABLE agentes (
    id_agente INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    email_agente VARCHAR(100) UNIQUE,
    telefono_agente VARCHAR(20),
    fecha_contratacion DATE
);

-- Tabla agentesMetadatatos
CREATE TABLE agentesMetadatatos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    id_agente INT NOT NULL,
    creadoEn DATETIME NOT NULL,
    creadoPor INT NOT NULL,
    actualizadoEn DATETIME NOT NULL,
    actualizadoPor INT NOT NULL,
    archivado BOOLEAN NOT NULL,
    archivadoEn DATETIME,
    archivadoPor INT,
    FOREIGN KEY (id_agente) REFERENCES agentes(id_agente) ON DELETE CASCADE,
    FOREIGN KEY (creadoPor) REFERENCES clientes(id_cliente),
    FOREIGN KEY (actualizadoPor) REFERENCES clientes(id_cliente),
    FOREIGN KEY (archivadoPor) REFERENCES clientes(id_cliente) ON DELETE SET NULL
);

-- Tabla interacciones
CREATE TABLE interacciones (
    id_interaccion INT AUTO_INCREMENT PRIMARY KEY,
    id_deuda INT NOT NULL,
    id_agente INT NOT NULL,
    fecha_hora DATETIME DEFAULT CURRENT_TIMESTAMP,
    tipo_interaccion VARCHAR(50),
    canal VARCHAR(50),
    duracion INT,
    resultado VARCHAR(255),
    notas TEXT,
    FOREIGN KEY (id_deuda) REFERENCES deudas(id_deuda) ON DELETE CASCADE,
    FOREIGN KEY (id_agente) REFERENCES agentes(id_agente) ON DELETE CASCADE
);

-- Tabla planes_pago
CREATE TABLE planes_pago (
    id_plan INT AUTO_INCREMENT PRIMARY KEY,
    id_deuda INT NOT NULL,
    fecha_inicio DATE,
    fecha_fin DATE,
    monto_cuota DECIMAL(10,2),
    frecuencia VARCHAR(20),
    dia_de_pago INT,
    estado VARCHAR(20),
    FOREIGN KEY (id_deuda) REFERENCES deudas(id_deuda) ON DELETE CASCADE
);

CREATE INDEX idx_pp_estado ON planes_pago (estado);

-- Tabla registros
CREATE TABLE registros (
    id_registro INT AUTO_INCREMENT PRIMARY KEY,
    accion ENUM(
        'Creacion de usuario Cliente',
        'Actualización de usuario Cliente',
        'Inicio de sesión usuario Cliente',
        'Sesión finalizada usuario Cliente',
        'Creacion de usuario Agente',
        'Actualización de usuario Agente',
        'Inicio de sesión usuario Agente',
        'Sesión finalizada usuario Agente'
    ) NOT NULL,
    fecha DATETIME NOT NULL
);

-- Tabla alertas
CREATE TABLE alertas (
    id_alerta INT AUTO_INCREMENT PRIMARY KEY,
    registro_relacionado INT NOT NULL,
    alerta_interna BOOLEAN NOT NULL, -- agente
    agente INT,
    alerta_externa BOOLEAN NOT NULL, -- cliente
    cliente INT,
    tipo_de_alerta ENUM('Mora', 'Recordatorio', 'Aviso de pago', 'Actualización de deuda', 'Notificación general') NOT NULL,
    fecha_de_emision DATETIME NOT NULL,
    fecha_de_recepcion DATETIME NOT NULL,
    alerta_vista BOOLEAN,
    FOREIGN KEY (registro_relacionado) REFERENCES registros(id_registro) ON DELETE CASCADE,
    FOREIGN KEY (agente) REFERENCES agentes(id_agente) ON DELETE SET NULL,
    FOREIGN KEY (cliente) REFERENCES clientes(id_cliente) ON DELETE SET NULL
);

-- Funciones
DELIMITER //

-- 1. Calcular días de mora de una deuda
CREATE FUNCTION calcular_dias_mora(id_deuda_param INT) RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE dias_mora INT;
    DECLARE fecha_vencimiento DATE;
    
    SELECT fecha_vencimiento INTO fecha_vencimiento
    FROM deudas
    WHERE id_deuda = id_deuda_param;
    
    IF fecha_vencimiento < CURDATE() THEN
        SET dias_mora = DATEDIFF(CURDATE(), fecha_vencimiento);
    ELSE
        SET dias_mora = 0;
    END IF;
    
    RETURN dias_mora;
END //

-- 2. Calcular saldo pendiente con intereses
CREATE FUNCTION calcular_saldo_interes(id_deuda_param INT) RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    DECLARE saldo DECIMAL(10,2);
    DECLARE tasa DECIMAL(5,2);
    DECLARE dias_mora INT;
    
    SELECT monto_pendiente, COALESCE(tasa_interes, 0), calcular_dias_mora(id_deuda_param)
    INTO saldo, tasa, dias_mora
    FROM deudas
    WHERE id_deuda = id_deuda_param;
    
    RETURN saldo * (1 + (tasa / 100) * (dias_mora / 30.0));
END //

-- Triggers
-- 1. Actualizar monto pendiente después de un pago
CREATE TRIGGER tr_actualizar_saldo
AFTER INSERT ON pagos
FOR EACH ROW
BEGIN
    UPDATE deudas
    SET monto_pendiente = monto_pendiente - NEW.monto_pagado
    WHERE id_deuda = NEW.id_deuda;
END //

-- 2. Registrar creación de clientes
CREATE TRIGGER tr_registro_cliente
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO registros(accion, fecha)
    VALUES ('Creacion de usuario Cliente', NOW());
END //

-- 3. Generar alerta por deuda vencida (INSERT)
CREATE TRIGGER tr_alerta_mora_insert
AFTER INSERT ON deudas
FOR EACH ROW
BEGIN
    IF NEW.fecha_vencimiento < CURDATE() AND NEW.monto_pendiente > 0 THEN
        INSERT INTO registros(accion, fecha) VALUES ('Notificación general', NOW());
        
        INSERT INTO alertas(
            registro_relacionado,
            alerta_interna,
            alerta_externa,
            cliente,
            tipo_de_alerta,
            fecha_de_emision,
            fecha_de_recepcion,
            alerta_vista
        )
        VALUES (
            LAST_INSERT_ID(),
            TRUE,
            TRUE,
            NEW.id_cliente,
            'Mora',
            NOW(),
            NOW(),
            FALSE
        );
    END IF;
END //

-- 4. Generar alerta por deuda vencida (UPDATE)
CREATE TRIGGER tr_alerta_mora_update
AFTER UPDATE ON deudas
FOR EACH ROW
BEGIN
    IF NEW.fecha_vencimiento < CURDATE() AND NEW.monto_pendiente > 0 THEN
        INSERT INTO registros(accion, fecha) VALUES ('Notificación general', NOW());
        
        INSERT INTO alertas(
            registro_relacionado,
            alerta_interna,
            alerta_externa,
            cliente,
            tipo_de_alerta,
            fecha_de_emision,
            fecha_de_recepcion,
            alerta_vista
        )
        VALUES (
            LAST_INSERT_ID(),
            TRUE,
            TRUE,
            NEW.id_cliente,
            'Mora',
            NOW(),
            NOW(),
            FALSE
        );
    END IF;
END //

-- 5. Actualizar estado de planes de pago
CREATE TRIGGER tr_actualizar_plan_pago
AFTER UPDATE ON deudas
FOR EACH ROW
BEGIN
    IF NEW.monto_pendiente = 0 THEN
        UPDATE planes_pago
        SET estado = 'Pagado'
        WHERE id_deuda = NEW.id_deuda AND estado != 'Pagado';
    END IF;
END //

-- 6. Auditoría de actualización de clientes
CREATE TRIGGER tr_auditar_cliente
AFTER UPDATE ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO clientesMetadatos(
        cliente_id,
        creadoEn,
        creadoPor,
        actualizadoEn,
        actualizadoPor,
        archivado
    )
    VALUES (
        OLD.id_cliente,
        OLD.fecha_registro,
        1,  -- ID de sistema/usuario admin
        NOW(),
        1,  -- ID de sistema/usuario admin
        FALSE
    );
END //

-- Procedimientos almacenados
-- 1. Registrar pago y actualizar deuda
CREATE PROCEDURE registrar_pago(
    IN deuda_id INT,
    IN monto DECIMAL(10,2),
    IN metodo VARCHAR(50),
    IN referencia_pago VARCHAR(100)
)
BEGIN
    INSERT INTO pagos(id_deuda, fecha_pago, monto_pagado, metodo_pago, referencia)
    VALUES (deuda_id, CURDATE(), monto, metodo, referencia_pago);
    
    -- El trigger se encargará de actualizar el monto pendiente
END //

-- 2. Generar plan de pago
CREATE PROCEDURE crear_plan_pago(
    IN deuda_id INT,
    IN cuota DECIMAL(10,2),
    IN frecuencia_pago VARCHAR(20),
    IN dia_pago INT
)
BEGIN
    DECLARE fecha_inicio DATE DEFAULT CURDATE();
    DECLARE fecha_fin DATE;
    
    IF frecuencia_pago = 'Mensual' THEN
        SET fecha_fin = DATE_ADD(fecha_inicio, INTERVAL 6 MONTH);
    ELSEIF frecuencia_pago = 'Quincenal' THEN
        SET fecha_fin = DATE_ADD(fecha_inicio, INTERVAL 3 MONTH);
    ELSE
        SET fecha_fin = DATE_ADD(fecha_inicio, INTERVAL 1 MONTH);
    END IF;
    
    INSERT INTO planes_pago(
        id_deuda, 
        fecha_inicio, 
        fecha_fin, 
        monto_cuota, 
        frecuencia, 
        dia_de_pago, 
        estado
    )
    VALUES (
        deuda_id,
        fecha_inicio,
        fecha_fin,
        cuota,
        frecuencia_pago,
        dia_pago,
        'Activo'
    );
END //

-- 3. Reporte diario de morosidad
CREATE PROCEDURE generar_reporte_morosidad()
BEGIN
    DECLARE registro_id INT;
    
    INSERT INTO registros(accion, fecha) VALUES ('Notificación general', NOW());
    SET registro_id = LAST_INSERT_ID();
    
    INSERT INTO alertas(
        registro_relacionado,
        alerta_interna,
        agente,
        alerta_externa,
        tipo_de_alerta,
        fecha_de_emision,
        fecha_de_recepcion,
        alerta_vista
    )
    SELECT 
        registro_id,
        TRUE,
        a.id_agente,
        FALSE,
        'Mora',
        NOW(),
        NOW(),
        FALSE
    FROM deudas d
    JOIN clientes c ON d.id_cliente = c.id_cliente
    JOIN agentes a ON a.id_agente = (SELECT id_agente FROM interacciones 
                                     WHERE id_deuda = d.id_deuda 
                                     ORDER BY fecha_hora DESC LIMIT 1)
    WHERE d.fecha_vencimiento < CURDATE()
    AND d.monto_pendiente > 0;
END //

DELIMITER ;

-- Views
-- 1. Vista de Cartera Vencida (Deudas con mora)
CREATE VIEW vw_cartera_vencida AS
SELECT 
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    d.id_deuda,
    d.monto_original,
    d.monto_pendiente,
    d.fecha_vencimiento,
    calcular_dias_mora(d.id_deuda) AS dias_mora,
    calcular_saldo_interes(d.id_deuda) AS saldo_con_interes,
    d.tipo_deuda,
    a.id_agente,
    CONCAT(a.nombre, ' ', a.apellido) AS agente_asignado
FROM deudas d
JOIN clientes c ON d.id_cliente = c.id_cliente
LEFT JOIN (
    SELECT id_deuda, id_agente
    FROM interacciones
    WHERE id_interaccion IN (
        SELECT MAX(id_interaccion)
        FROM interacciones
        GROUP BY id_deuda
    )
) ult_inter ON d.id_deuda = ult_inter.id_deuda
LEFT JOIN agentes a ON ult_inter.id_agente = a.id_agente
WHERE d.monto_pendiente > 0
AND d.fecha_vencimiento < CURDATE();

-- 2. Vista de Efectividad de Agentes
CREATE VIEW vw_efectividad_agentes AS
SELECT 
    a.id_agente,
    CONCAT(a.nombre, ' ', a.apellido) AS agente,
    COUNT(DISTINCT i.id_deuda) AS deudas_gestionadas,
    SUM(CASE WHEN d.monto_pendiente = 0 THEN 1 ELSE 0 END) AS deudas_liquidadas,
    SUM(p.monto_pagado) AS total_recaudado,
    AVG(i.duracion) AS duracion_promedio_interaccion,
    COUNT(i.id_interaccion) AS total_interacciones
FROM agentes a
LEFT JOIN interacciones i ON a.id_agente = i.id_agente
LEFT JOIN deudas d ON i.id_deuda = d.id_deuda
LEFT JOIN pagos p ON d.id_deuda = p.id_deuda
GROUP BY a.id_agente;

-- 3. Vista de Historial de Pagos por Cliente
CREATE VIEW vw_historial_pagos_cliente AS
SELECT 
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    d.id_deuda,
    d.tipo_deuda,
    p.fecha_pago,
    p.monto_pagado,
    p.metodo_pago,
    (SELECT SUM(monto_pagado) 
     FROM pagos p2 
     WHERE p2.id_deuda = d.id_deuda 
     AND p2.fecha_pago <= p.fecha_pago) AS acumulado_deuda,
    d.monto_original
FROM clientes c
JOIN deudas d ON c.id_cliente = d.id_cliente
JOIN pagos p ON d.id_deuda = p.id_deuda;

-- 4. Vista de Planes de Pago con Estado
CREATE VIEW vw_estado_planes_pago AS
SELECT 
    pp.id_plan,
    d.id_deuda,
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    pp.fecha_inicio,
    pp.fecha_fin,
    pp.monto_cuota,
    pp.frecuencia,
    pp.dia_de_pago,
    pp.estado,
    d.monto_pendiente,
    (d.monto_original - d.monto_pendiente) AS total_pagado,
    (SELECT SUM(monto_pagado)
     FROM pagos p
     WHERE p.id_deuda = d.id_deuda
     AND p.fecha_pago BETWEEN pp.fecha_inicio AND COALESCE(pp.fecha_fin, CURDATE())) AS pagado_en_plan
FROM planes_pago pp
JOIN deudas d ON pp.id_deuda = d.id_deuda
JOIN clientes c ON d.id_cliente = c.id_cliente;

-- 5. Vista de Alertas Pendientes
CREATE VIEW vw_alertas_pendientes AS
SELECT 
    a.id_alerta,
    a.tipo_de_alerta,
    a.fecha_de_emision,
    TIMESTAMPDIFF(HOUR, a.fecha_de_emision, NOW()) AS horas_pendientes,
    CASE 
        WHEN a.alerta_interna THEN CONCAT('Agente: ', ag.nombre, ' ', ag.apellido)
        WHEN a.alerta_externa THEN CONCAT('Cliente: ', c.nombre, ' ', c.apellido)
        ELSE 'Sistema'
    END AS destinatario,
    r.accion AS evento_origen,
    d.id_deuda,
    d.monto_pendiente,
    calcular_dias_mora(d.id_deuda) AS dias_mora
FROM alertas a
JOIN registros r ON a.registro_relacionado = r.id_registro
LEFT JOIN clientes c ON a.cliente = c.id_cliente
LEFT JOIN agentes ag ON a.agente = ag.id_agente
LEFT JOIN deudas d ON c.id_cliente = d.id_cliente
WHERE a.alerta_vista = FALSE;