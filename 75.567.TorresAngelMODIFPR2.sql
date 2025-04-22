SET search_path TO ubd_20242;
--Pregunta 1
CREATE OR REPLACE FUNCTION update_report_customer(p_customer_id INT)
RETURNS REPORT_CUSTOMER_TYPE AS $$
DECLARE
    v_customer_name VARCHAR(100);
    v_total_spent DECIMAL(10,2);
    v_total_spent_no_grape DECIMAL(10,2);
    v_total_orders INTEGER;
    v_favorite_wine_name VARCHAR(100);
    v_favorite_winery_name VARCHAR(100);
    v_result REPORT_CUSTOMER_TYPE;
    v_customer_exists BOOLEAN;
    v_has_orders BOOLEAN;
BEGIN
    -- Verificar si el cliente existe
    SELECT EXISTS(SELECT 1 FROM CUSTOMER WHERE customer_id = p_customer_id) INTO v_customer_exists;
    
    IF NOT v_customer_exists THEN
        RAISE EXCEPTION 'No existe ningún cliente con el identificador %', p_customer_id;
    END IF;
    
    -- Obtener el nombre del cliente
    SELECT customer_name INTO v_customer_name
    FROM CUSTOMER
    WHERE customer_id = p_customer_id;
    
    -- Verificar si el cliente tiene pedidos
    SELECT EXISTS(
        SELECT 1 
        FROM CUSTOMER_ORDER 
        WHERE customer_id = p_customer_id
    ) INTO v_has_orders;
    
    IF NOT v_has_orders THEN
        -- Crear un resultado con valores nulos para los campos relacionados con pedidos
        v_result := (p_customer_id, v_customer_name, NULL, NULL, 0, NULL, NULL);
        
        -- Actualizar o insertar en la tabla REPORT_CUSTOMER
        INSERT INTO REPORT_CUSTOMER (
            customer_id, customer_name, total_spent, total_spent_no_grape, 
            total_orders, favorite_wine_name, favorite_winery_name
        ) 
        VALUES (
            p_customer_id, v_customer_name, NULL, NULL, 
            0, NULL, NULL
        )
        ON CONFLICT (customer_id) 
        DO UPDATE SET
            customer_name = v_customer_name,
            total_spent = NULL,
            total_spent_no_grape = NULL,
            total_orders = 0,
            favorite_wine_name = NULL,
            favorite_winery_name = NULL;
            
        RAISE NOTICE 'El cliente % no tiene pedidos', p_customer_id;
        RETURN v_result;
    END IF;
    
    -- Calcular el número total de pedidos
    SELECT COUNT(*) INTO v_total_orders
    FROM CUSTOMER_ORDER
    WHERE customer_id = p_customer_id;
    
    -- Calcular el total gastado por el cliente
    SELECT COALESCE(SUM(
        ol.quantity * w.price * 
        CASE 
            WHEN ol.discount IS NOT NULL THEN (1 - ol.discount::DECIMAL / 100) 
            ELSE 1 
        END
    ), 0) INTO v_total_spent
    FROM CUSTOMER_ORDER co
    JOIN ORDER_LINE ol ON co.order_id = ol.order_id
    JOIN WINE w ON ol.wine_id = w.wine_id
    WHERE co.customer_id = p_customer_id;
    
    -- Calcular el total gastado en vinos sin variedad de uva
    SELECT COALESCE(SUM(
        ol.quantity * w.price * 
        CASE 
            WHEN ol.discount IS NOT NULL THEN (1 - ol.discount::DECIMAL / 100) 
            ELSE 1 
        END
    ), 0) INTO v_total_spent_no_grape
    FROM CUSTOMER_ORDER co
    JOIN ORDER_LINE ol ON co.order_id = ol.order_id
    JOIN WINE w ON ol.wine_id = w.wine_id
    LEFT JOIN WINE_GRAPE wg ON w.wine_id = wg.wine_id
    WHERE co.customer_id = p_customer_id
    AND wg.grape_id IS NULL;
    
    -- Encontrar el vino favorito y su bodega
    WITH wine_counts AS (
        SELECT 
            w.wine_id,
            w.wine_name,
            winery.winery_name,
            COUNT(*) AS order_count,
            MAX(co.order_date) AS latest_order
        FROM CUSTOMER_ORDER co
        JOIN ORDER_LINE ol ON co.order_id = ol.order_id
        JOIN WINE w ON ol.wine_id = w.wine_id
        JOIN WINERY ON w.winery_id = WINERY.winery_id
        WHERE co.customer_id = p_customer_id
        GROUP BY w.wine_id, w.wine_name, winery.winery_name
    ),
    ranked_wines AS (
        SELECT 
            wine_name,
            winery_name,
            ROW_NUMBER() OVER (
                ORDER BY 
                    order_count DESC, 
                    latest_order DESC,
                    wine_name ASC
            ) AS rank
        FROM wine_counts
    )
    SELECT 
        wine_name, 
        winery_name 
    INTO 
        v_favorite_wine_name, 
        v_favorite_winery_name
    FROM ranked_wines
    WHERE rank = 1;
    
    -- Preparar el resultado
    v_result := (
        p_customer_id, 
        v_customer_name, 
        v_total_spent, 
        v_total_spent_no_grape, 
        v_total_orders, 
        v_favorite_wine_name, 
        v_favorite_winery_name
    );
    
    -- Actualizar o insertar en la tabla REPORT_CUSTOMER
    INSERT INTO REPORT_CUSTOMER (
        customer_id, customer_name, total_spent, total_spent_no_grape, 
        total_orders, favorite_wine_name, favorite_winery_name
    ) 
    VALUES (
        p_customer_id, v_customer_name, v_total_spent, v_total_spent_no_grape, 
        v_total_orders, v_favorite_wine_name, v_favorite_winery_name
    )
    ON CONFLICT (customer_id) 
    DO UPDATE SET
        customer_name = v_customer_name,
        total_spent = v_total_spent,
        total_spent_no_grape = v_total_spent_no_grape,
        total_orders = v_total_orders,
        favorite_wine_name = v_favorite_wine_name,
        favorite_winery_name = v_favorite_winery_name;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;
--Pregunta 2
-- Función que será llamada por el trigger
CREATE OR REPLACE FUNCTION check_wine_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_count INTEGER;
    v_pdo_name VARCHAR(100);
BEGIN
    -- Obtener el nombre de la PDO
    SELECT pdo_name INTO v_pdo_name
    FROM PDO
    WHERE pdo_id = NEW.pdo_id;
    
    -- Excluir 'La Rioja' de la comprobación
    IF v_pdo_name = 'La Rioja' THEN
        RETURN NEW;
    END IF;
    
    -- Contar vinos con la misma añada y PDO
    SELECT COUNT(*) INTO v_count
    FROM WINE
    WHERE vintage = NEW.vintage
      AND pdo_id = NEW.pdo_id
      AND (TG_OP = 'UPDATE' AND wine_id != NEW.wine_id OR TG_OP = 'INSERT');
    
    -- Verificar si se supera el límite
    IF v_count >= 3 THEN
        RAISE EXCEPTION 'No se permiten más de 3 vinos con la misma añada (%) y denominación de origen (%)', 
            NEW.vintage, v_pdo_name;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear el trigger
CREATE TRIGGER check_wine_limit_trigger
BEFORE INSERT OR UPDATE ON WINE
FOR EACH ROW
EXECUTE FUNCTION check_wine_limit();




