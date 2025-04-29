-- Drop and create the REPORT_CUSTOMER_TYPE in ubd_20242
DROP TYPE IF EXISTS ubd_20242.REPORT_CUSTOMER_TYPE CASCADE;

CREATE TYPE ubd_20242.REPORT_CUSTOMER_TYPE AS (
    t_customer_id SMALLINT,
    t_customer_name VARCHAR(255),
    t_total_spent DECIMAL(10,2),
    t_total_spent_no_grape DECIMAL(10,2),
    t_total_orders INTEGER,
    t_favorite_wine_name VARCHAR(100),
    t_favorite_winery_name VARCHAR(100)
);

-- Create the report_customer table in ubd_20242
CREATE TABLE IF NOT EXISTS ubd_20242.report_customer (
    customer_id INT PRIMARY KEY,
    customer_name VARCHAR(255),
    total_spent DECIMAL(10,2),
    total_spent_no_grape DECIMAL(10,2),
    total_orders INTEGER,
    favorite_wine_name VARCHAR(100),
    favorite_winery_name VARCHAR(100)
);

-- Create or replace the function in ubd_20242
CREATE OR REPLACE FUNCTION ubd_20242.update_report_customer(p_customer_id INT)
RETURNS ubd_20242.REPORT_CUSTOMER_TYPE AS $$
DECLARE
    v_customer_name VARCHAR(255);
    v_total_spent DECIMAL(10,2);
    v_total_spent_no_grape DECIMAL(10,2);
    v_total_orders INTEGER;
    v_favorite_wine_name VARCHAR(100);
    v_favorite_winery_name VARCHAR(100);
    v_result ubd_20242.REPORT_CUSTOMER_TYPE;
    v_customer_exists BOOLEAN;
    v_has_orders BOOLEAN;
BEGIN
    -- Check if customer exists
    SELECT EXISTS (
        SELECT 1 FROM ubd_20242.customer WHERE customer_id = p_customer_id
    ) INTO v_customer_exists;

    IF NOT v_customer_exists THEN
        RAISE EXCEPTION 'No existe ningún cliente con el identificador [%]', p_customer_id;
    END IF;

    -- Get customer name
    SELECT customer_name INTO v_customer_name
    FROM ubd_20242.customer
    WHERE customer_id = p_customer_id;

    -- Check if customer has orders
    SELECT EXISTS (
        SELECT 1 FROM ubd_20242.customer_order WHERE customer_id = p_customer_id
    ) INTO v_has_orders;

    IF NOT v_has_orders THEN
        -- No orders: return and insert default values
        v_result := (p_customer_id::SMALLINT, v_customer_name, NULL, NULL, 0, NULL, NULL);

        INSERT INTO ubd_20242.report_customer (
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
    FROM ubd_20242.customer_order
    WHERE customer_id = p_customer_id;

    -- Calculate total spent
    SELECT COALESCE(SUM(
        ol.quantity * w.price *
        CASE
            WHEN ol.discount IS NOT NULL THEN (1 - ol.discount::DECIMAL/100)
            ELSE 1
        END
    ), 0)
    INTO v_total_spent
    FROM ubd_20242.customer_order co
    JOIN ubd_20242.order_line ol ON co.order_id = ol.order_id
    JOIN ubd_20242.wine w ON ol.wine_id = w.wine_id
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
    FROM ubd_20242.customer_order co
    JOIN ubd_20242.order_line ol ON co.order_id = ol.order_id
    JOIN ubd_20242.wine w ON ol.wine_id = w.wine_id
    LEFT JOIN ubd_20242.wine_grape wg ON w.wine_id = wg.wine_id
    WHERE co.customer_id = p_customer_id
      AND wg.grape_id IS NULL;

    -- Determine favorite wine and winery
    WITH wine_count AS (
        SELECT
            w.wine_id, w.wine_name, wi.winery_name,
            COUNT(*) AS order_count,
            MAX(co.order_date) AS latest_order
        FROM ubd_20242.customer_order co
        JOIN ubd_20242.order_line ol ON co.order_id = ol.order_id
        JOIN ubd_20242.wine w ON ol.wine_id = w.wine_id
        JOIN ubd_20242.winery wi ON w.winery_id = wi.winery_id
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

    -- Build result
    v_result := (
        p_customer_id::SMALLINT,
        v_customer_name,
        v_total_spent,
        v_total_spent_no_grape,
        v_total_orders,
        v_favorite_wine_name,
        v_favorite_winery_name
    );

    -- Insert or update report_customer
    INSERT INTO ubd_20242.report_customer (
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

    -- Return result
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;