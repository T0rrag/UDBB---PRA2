CREATE OR REPLACE FUNCTION update_report_customer (p_customer_id INT)
RETURNS REPORT_CUSTOMER_TYPE AS $$

-- Var declaration

DECLARE
	v_customer_name VARCHAR(100);
	v_total_spent DECIMAL(10,2);
	v_total_spent_no_grape DECIMAL (10,2);
	v_total_orders INTEGER;
	v_favorite_wine_name VARCHAR(100);
	v_favorite_winery_name VARCHAR(100;
	v_result REPORT_CUSTOMER_TYPE;
	v_customer_exists BOOLEAN;
	v_has_orders BOOLEAN;

-- Check if client exists
-- If exist
SELECT EXISTS(SELECT 1 FROM CUSTOMER WHERE customer_id = p_customer_id) INTO v_customer_exists;

-- Else
IF NOT v_customer_exists THEN
	RAISE EXCEPTION "No existe ningún cliente con el identificador que se ha indicado [%]", p_customer_id;
END IF;

-- Get Client (if exists)
SELECT customer_name INTO v_customer_name
FROM CUSTOMER
WHERE customer_id = p_customer_id;

-- Check orders
-- if it has orders
SELECT EXISTS (
	SELECT 1
	FROM CUSTOMER_ORDER
	WHERE customer_id = p_customer_id
	) into v_has_orders;

--else
IF NOT v_has_orders THEN
	v_result := (p_customer_id, v_customer_name, NULL, NULL, 0, NULL, NULL);

--Insert into REPORT_CUSTOMER
INSERT INTO REPORT_CUSTOMER (
	customer_id, customer_name, total_spent, total_spent_no_grape, total_orders, favorite_wine_name, favorite_winery_name
	)
	VALUES (
		p_customer_id, v_customer_name, NULL, NULL, 0, NULL, NULL)

	ON CONFLICT (customer_id)
	DO UPDATE SET
		customer_name = v_customer_name,
		total_spent = NULL,
		total_spent_no_grape = NULL,
		total_orders =0,
		favorite_wine_name = NULL,
		favorite_winery_name = NULL;

	RAISE NOTICE "El cliente % no tiene pedidos", p_customer_id;
	RETURN v_result;
END IF;

--Calculate total orders

SELECT COUNT(*) INTO v_total_orders
FROM CUSTOMER_ORDER
WHERE customer_id = p_customer_id;

--Calculate total spent
-- referred to: quantity-price-discount
SELECT COALESCE (SUM(
	ol.quantity*w.price*
	CASE
	--if a discount is needed
		WHEN ol-discount IS NOT NULL THEN (1-ol.discount::DECIMAL/100)
		ELSE 1
	END), 0) 

-- Add to total_spent
INTO v_total_spent_no_grape
	FROM CUSTOMER_ORDER co
	JOIN ORDER_LINE ol ON co.order_id = ol.order_id
	JOIN WINE w ON ol.wine_id = w.wine_id
	LEFT JOIN WINE_GRAPE wg ON w.wine_id = wg.wine_id
	WHERE co.customer_id = p_customer_id
	AND wg.grape_id IS NULL;

--Favourite wine & winery
--create counter for wines, sort it and get the wine with most values
WITH wine_count AS (
	SELECT
		w.wine_id, w.wine_name, winery.winery_name, 
		COUNT(*) AS order_count,
		MAX(co.order_date) AS latest_order

--pass to a group by
FROM CUSTOMER_ORDER co
JOIN ORDER_LINE ol ON co.order_id = ol.order_id
JOIN WINE w ON ol.wine_id = w.wine_id
JOIN WINERY ON w.winery_id = WINERY.winery_id
WHERE co.customer_id = p_customer_id
GROUP BY w.wine_id, w.wine_name, winery.winery_name
),

--Order the wine table to get a favourite (top rated = highest bought)
ranked_wines AS
	SELECT
		wine_name, winery_name,
		ROW_NUMBER() OVER (
			ORDER BY
				order_count DESC, latest_order DESC, wine_name ASC)
				AS rank
			FROM wine_counts
		)
		SELECT
		wine_name, winery_name
		INTO
		v_favorite_wine_name, v_favorite_winery_name
		FROM ranked_wines
		WHERE rank = 1;
		)

)

)