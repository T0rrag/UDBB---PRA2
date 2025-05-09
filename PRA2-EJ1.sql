-- Primero, crea el tipo si no existe (si no lo tienes ya creado)
DROP TYPE IF EXISTS REPORT_CUSTOMER_TYPE;

CREATE TYPE REPORT_CUSTOMER_TYPE AS (
    t_customer_id SMALLINT,
    t_customer_name VARCHAR(255),
    t_total_spent DECIMAL(10,2),
    t_total_spent_no_grape DECIMAL(10,2),
    t_total_orders INTEGER,
    t_favorite_wine_name VARCHAR(100),
    t_favorite_winery_name VARCHAR(100)
);

-- Ahora la función completa corregida:
DROP TYPE IF EXISTS update_report_customer(p_customer_id INT) CASCADE
RETURNS REPORT_CUSTOMER_TYPE AS $$

-- Var declaration
DECLARE
    v_customer_name VARCHAR(255);
    v_total_spent DECIMAL(10,2);
    v_total_spent_no_grape DECIMAL(10,2);
    v_total_orders INTEGER;
    v_favorite_wine_name VARCHAR(100);
    v_favorite_winery_name VARCHAR(100);
    v_result REPORT_CUSTOMER_TYPE;
    v_customer_exists BOOLEAN;
    v_has_orders BOOLEAN;

-- Check if client exists
BEGIN
    -- If exist
    SELECT EXISTS (
        SELECT 1 FROM customer WHERE customer_id = p_customer_id
    ) INTO v_customer_exists;

    -- Else
    IF NOT v_customer_exists THEN
        RAISE EXCEPTION 'No existe ningún cliente con el identificador [%]', p_customer_id;
    END IF;

    -- Get Client (if exists)
    SELECT customer_name INTO v_customer_name
    FROM customer
    WHERE customer_id = p_customer_id;

    -- Check orders
    -- if it has orders
    SELECT EXISTS (
        SELECT 1 FROM customer_order WHERE customer_id = p_customer_id
    ) INTO v_has_orders;

    -- else
    IF NOT v_has_orders THEN
        -- If no orders, build the result with NULLs
        v_result := (p_customer_id, v_customer_name, NULL, NULL, 0, NULL, NULL);

        -- Insert into REPORT_CUSTOMER
        INSERT INTO report_customer (
            customer_id, customer_name, total_spent, total_spent_no_grape,
            total_orders, favorite_wine_name, favorite_winery_name
        )
        VALUES (
            p_customer_id, v_customer_name, NULL, NULL, 0, NULL, NULL
        )
        ON CONFLICT (customer_id)
        DO UPDATE SET
            customer_name = EXCLUDED.customer_name,
            total_spent = EXCLUDED.total_spent,
            total_spent_no_grape = EXCLUDED.total_spent_no_grape,
            total_orders = EXCLUDED.total_orders,
            favorite_wine_name = EXCLUDED.favorite_wine_name,
            favorite_winery_name = EXCLUDED.favorite_winery_name;

        RAISE NOTICE 'El cliente % no tiene pedidos.', p_customer_id;
        RETURN v_result;
    END IF;

    -- Calculate total orders
    SELECT COUNT(DISTINCT order_id)
    INTO v_total_orders
    FROM customer_order
    WHERE customer_id = p_customer_id;

    -- Calculate total spent
    -- referred to: quantity * price * (1 - discount%)
    SELECT COALESCE(SUM(
        ol.quantity * w.price *
        CASE
            -- if a discount is needed
            WHEN ol.discount IS NOT NULL THEN (1 - ol.discount::DECIMAL/100)
            ELSE 1
        END
    ), 0)
    INTO v_total_spent
    FROM customer_order co
    JOIN order_line ol ON co.order_id = ol.order_id
    JOIN wine w ON ol.wine_id = w.wine_id
    WHERE co.customer_id = p_customer_id;

    -- Calculate total spent on wines without grape
    SELECT COALESCE(SUM(
        ol.quantity * w.price *
        CASE
            WHEN ol.discount IS NOT NULL THEN (1 - ol.discount::DECIMAL/100)
            ELSE 1
        END
    ), 0)
    INTO v_total_spent_no_grape
    FROM customer_order co
    JOIN order_line ol ON co.order_id = ol.order_id
    JOIN wine w ON ol.wine_id = w.wine_id
    LEFT JOIN wine_grape wg ON w.wine_id = wg.wine_id
    WHERE co.customer_id = p_customer_id
      AND wg.grape_id IS NULL;

    -- Favourite wine & winery
    -- Create counter for wines, sort it and get the wine with most values
    WITH wine_count AS (
        SELECT
            w.wine_id, w.wine_name, wi.winery_name,
            COUNT(*) AS order_count,
            MAX(co.order_date) AS latest_order
        FROM customer_order co
        JOIN order_line ol ON co.order_id = ol.order_id
        JOIN wine w ON ol.wine_id = w.wine_id
        JOIN winery wi ON w.winery_id = wi.winery_id
        WHERE co.customer_id = p_customer_id
        GROUP BY w.wine_id, w.wine_name, wi.winery_name
    ),
    ranked_wines AS (
        SELECT
            wine_name, winery_name,
            ROW_NUMBER() OVER (
                ORDER BY order_count DESC, latest_order DESC, wine_name ASC
            ) AS rank
        FROM wine_count
    )
    SELECT wine_name, winery_name
    INTO v_favorite_wine_name, v_favorite_winery_name
    FROM ranked_wines
    WHERE rank = 1;

    -- Format result
    v_result := (
        p_customer_id,
        v_customer_name,
        v_total_spent,
        v_total_spent_no_grape,
        v_total_orders,
        v_favorite_wine_name,
        v_favorite_winery_name
    );

    -- Update & insert into REPORT_CUSTOMER
    INSERT INTO report_customer (
        customer_id, customer_name, total_spent, total_spent_no_grape,
        total_orders, favorite_wine_name, favorite_winery_name
    )
    VALUES (
        p_customer_id, v_customer_name, v_total_spent, v_total_spent_no_grape,
        v_total_orders, v_favorite_wine_name, v_favorite_winery_name
    )
    ON CONFLICT (customer_id)
    DO UPDATE SET
        customer_name = EXCLUDED.customer_name,
        total_spent = EXCLUDED.total_spent,
        total_spent_no_grape = EXCLUDED.total_spent_no_grape,
        total_orders = EXCLUDED.total_orders,
        favorite_wine_name = EXCLUDED.favorite_wine_name,
        favorite_winery_name = EXCLUDED.favorite_winery_name;

    -- Return final result
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;
