Use CocktailApp

USE CocktailApp

-- liczba orderów na dany stolik----------------------------
CREATE VIEW v_TableOrders AS
SELECT 
    T.id AS TableID, 
    T.table_number AS TableNumber, 
    COUNT(O.id) AS NumberOfOrders
FROM 
    [table] AS T 
LEFT JOIN 
    [order] AS O 
ON 
    T.id = O.table_id
GROUP BY 
    T.id, 
    T.table_number;

SELECT * FROM v_TableOrders
--------------------------------------------------------------

--wszystkie koktajle--------------------------------------------------------------
CREATE VIEW AllCocktails AS
SELECT c.id, c.price, c.description, c.image, cat.name AS category_name
FROM cocktail c
JOIN category cat ON c.category_id = cat.id;

SELECT * FROM AllCocktails;
--wszyscy pracownicy--------------------------------------------------------------
CREATE VIEW AllEmployees AS
SELECT *
FROM employees;

SELECT * FROM AllEmployees;
----------------------------------------------------------------------------------------------------------------------------


---najcześciej zamawiane koktajle-----------------------------------------------
CREATE VIEW v_MostOrderedCocktails AS
SELECT TOP 100 PERCENT
    C.name AS CocktailName, 
    COUNT(OD.id) AS NumberOfOrders
FROM 
    Cocktail AS C
JOIN 
    Order_Details AS OD 
ON 
    C.id = OD.cocktail_id
GROUP BY 
    C.name
ORDER BY 
    NumberOfOrders DESC;

SELECT * FROM v_MostOrderedCocktails
----------------------------------------------------------------------------------------------------------------------------


--wyszukiwanie drinka-----------------------------------------------------------------------------------------------------------
CREATE FUNCTION GetCocktailsByPrefix(@prefix NVARCHAR(255))
RETURNS TABLE 
AS 
RETURN 
(
    SELECT id, name, price, description, image, category_id, is_custom
    FROM Cocktail
    WHERE name LIKE '%' + @prefix + '%'
);

SELECT * FROM GetCocktailsByPrefix('Mar'); 
--tworzenie skargi----------------------------------------------------------------------------------------------------------

CREATE PROCEDURE CreateComplaint
    @order_id INTEGER,
    @complaint_text TEXT,
    @complaint_date DATETIME,
    @complaint_status VARCHAR
AS
BEGIN
    INSERT INTO complaint (order_id, complaint_text, complaint_date, complaint_status)
    VALUES (@order_id, @complaint_text, @complaint_date, @complaint_status);
END;
SELECT * FROM complaint
EXEC CreateComplaint 
    @order_id = 1, 
    @complaint_text = 'The product was damaged.', 
    @complaint_date = '2023-06-10', 
    @complaint_status = 'Resolved';

----------------------------------------------------------------------------------------------------------------------------

--składanie zamówienia----------------------------------------------------------------------------------------------------------------------------
CREATE PROCEDURE PlaceOrder 
    @table_id INTEGER,
    @employee_id INTEGER,
    @order_date DATETIME,
    @is_complaint BIT,
	@cocktail_id INTEGER, 
	@quantity INTEGER
AS
BEGIN
    -- Dodawanie zam�wienia
    INSERT INTO [order] (table_id, employee_id, order_date, is_complaint)
    VALUES (@table_id, @employee_id, @order_date, @is_complaint);

    -- Pobieranie identyfikatora zam�wienia
    DECLARE @order_id INTEGER;
    SET @order_id = SCOPE_IDENTITY();

    -- Dodawanie szczeg��w zam�wienia
    INSERT INTO order_details (order_id, cocktail_id, quantity)
    VALUES (@order_id, @cocktail_id, @quantity);
END;

EXEC PlaceOrder 
    @table_id = 1, 
    @employee_id = 1, 
    @order_date = '2023-06-11', 
	@is_complaint = 0,
    @cocktail_id = 1, 
    @quantity = 2

SELECT * FROM [order]
SELECT * FROM order_details
---------------------------------------------------------------------------------------------------------------------------

--ilosc skarg na pracownikow-------------------------------------------------------------------------------------------------
CREATE VIEW EmployeeComplaints AS
SELECT e.id AS employee_id, e.first_name, e.last_name, COUNT(c.id) AS num_complaints
FROM employees e
LEFT JOIN [order] o ON e.id = o.employee_id
LEFT JOIN complaint c ON o.id = c.order_id
GROUP BY e.id, e.first_name, e.last_name

SELECT * FROM EmployeeComplaints;
----------------------------------------------------------------------------------------------------------------------------

-------spradzanie czy przy tworzeniu custom drinka jakis skladnik nie jest dodany wiecej niz 5 razy--------------------------------------------------------------------------------------------------
CREATE TRIGGER CheckCocktailIngredients
ON cocktail_ingredients
FOR INSERT, UPDATE
AS
BEGIN
  IF EXISTS (
    SELECT 1
    FROM inserted
    WHERE quantity > 5
  )
  BEGIN
    RAISERROR ('The quantity of ingredients cannot exceed 5.', 16, 1)
    ROLLBACK TRANSACTION
    RETURN
  END
END;

INSERT INTO cocktail_ingredients (cocktail_id, ingredient_id, quantity)
VALUES (1, 1, 3); -- replace with your actual cocktail_id and ingredient_id

SELECT * FROM cocktail_ingredients
----------------------------------------------------------------------------------------------------------------------------

--indeks na nazwe drinka, nazwa pracownika, nazwisko pracownika, numer stolika w orderze, numer zamowienia w complaint

-- Dodanie indeksu na pole "name" w tabeli "cocktail"
CREATE INDEX idx_cocktail_name ON cocktail(name);

-- Dodanie indeksu na pole "first_name" w tabeli "employees"
CREATE INDEX idx_employees_first_name ON employees(first_name);

-- Dodanie indeksu na pole "last_name" w tabeli "employees"
CREATE INDEX idx_employees_last_name ON employees(last_name);

-- Dodanie indeksu na pole "table_number" w tabeli "order"
CREATE INDEX idx_order_table_number ON [order](table_id);

-- Dodanie indeksu na pole "order_id" w tabeli "complaint"
CREATE INDEX idx_complaint_order_id ON complaint(order_id);
----------------------------------------------------------------------------------------------------------------------------

-----trigger czy ocena przekracza 5 gwiazdek----------------------------------------------------------------------------------------------------------
CREATE TRIGGER CheckRatingStars
ON rating
INSTEAD OF INSERT
AS
BEGIN
  -- Sprawdzenie, czy wprowadzone oceny przekraczaj� 5 gwiazdek
  IF EXISTS (SELECT * FROM inserted WHERE stars > 5)
  BEGIN
    -- Rzu� wyj�tek i anuluj wstawianie ocen
    RAISERROR('The rating exceeds the maximum value of 5 stars.', 16, 1);
    ROLLBACK;
  END
  ELSE
  BEGIN
    -- Wstaw poprawne oceny do tabeli rating
    INSERT INTO rating (id, stars, cocktail_id)
    SELECT id, stars, cocktail_id
    FROM inserted;
  END;
END;

INSERT INTO rating (stars, cocktail_id)
VALUES (6, 1);
----------------------------------------------------------------------------------------------------------

----po dodaniu skargi, ustawia flage is_complaint w zamówieniu na true-----------------------------------------------------------------------------------
CREATE TRIGGER SetOrderComplaintFlag
ON complaint
AFTER INSERT
AS
BEGIN
  -- Sprawd�, czy dodano now� skarg�
  IF EXISTS (SELECT * FROM inserted)
  BEGIN
    -- Aktualizuj flag� is_complaint na zam�wieniu powi�zanym ze skarg�
    UPDATE [order]
    SET is_complaint = 1
    WHERE id IN (SELECT order_id FROM inserted);
  END;
END;
select * FROM complaint;

INSERT INTO complaint (order_id, complaint_text, complaint_date, complaint_status)
VALUES (1, 'The order was incorrect.', GETDATE(), 'Pending');
-----------------------------------------------------------------------------------

CREATE TRIGGER CheckIngredientDuplication
ON ingredients
INSTEAD OF INSERT
AS
BEGIN
  IF EXISTS (
    SELECT i.ingredient_name
    FROM inserted i
    INNER JOIN ingredients ing
    ON i.ingredient_name = ing.ingredient_name
  )
  BEGIN
  PRINT('Podany składnik już istnieje') 
    ROLLBACK;
  END
  ELSE
  BEGIN
    -- Insert correct ingredients into ingredients table
    INSERT INTO ingredients (ingredient_name, price_unit)
    SELECT ingredient_name, price_unit
    FROM inserted;
  END;
END;

INSERT INTO ingredients (ingredient_name, price_unit) 
VALUES ('Vodka', 2.0) 

SELECT * FROM cocktail_ingredients
SELECT * FROM ingredients













































CREATE TABLE [order] (
  id INTEGER PRIMARY KEY IDENTITY,
  table_id INTEGER,
  employee_id INTEGER,
  order_date DATETIME,
  is_complaint BIT
);

CREATE TABLE order_details (
  id INTEGER PRIMARY KEY IDENTITY,
  order_id INTEGER,
  cocktail_id INTEGER,
  quantity INTEGER
);

CREATE TABLE payment (
  id INTEGER PRIMARY KEY IDENTITY,
  order_id INTEGER,
  amount FLOAT,
  payment_method_id INTEGER,
  payment_date DATETIME
);

CREATE TABLE payment_method (
  id INTEGER PRIMARY KEY IDENTITY,
  method VARCHAR(MAX)
);

CREATE TABLE rating (
  id INTEGER PRIMARY KEY IDENTITY,
  stars INTEGER,
  cocktail_id INTEGER
);

CREATE TABLE ingredients (
  id INTEGER PRIMARY KEY IDENTITY,
  ingredient_name VARCHAR(MAX),
  price_unit FLOAT
);

CREATE TABLE cocktail_ingredients(
  id INTEGER PRIMARY KEY IDENTITY,
  cocktail_id INTEGER,
  ingredient_id INTEGER,
  measurement_id INTEGER,
  quantity INTEGER,
  measurement_name VARCHAR(MAX),
  measurement INTEGER
);

CREATE TABLE cocktail (
  id INTEGER PRIMARY KEY IDENTITY,
  price FLOAT,
  description TEXT,
  image VARCHAR(MAX),
  category_id INTEGER,
  is_custom BIT
);

CREATE TABLE category (
  id INTEGER PRIMARY KEY IDENTITY,
  name VARCHAR(MAX)
);

CREATE TABLE employees (
  id INTEGER PRIMARY KEY IDENTITY,
  first_name VARCHAR(MAX),
  last_name VARCHAR(MAX),
  position VARCHAR(MAX),
  hire_date DATETIME,
  birth_date DATETIME,
  phone_number VARCHAR(MAX),
  city VARCHAR(MAX),
  post_code VARCHAR(MAX),
  address VARCHAR(MAX)
);

CREATE TABLE [table] (
  id INTEGER PRIMARY KEY IDENTITY,
  table_number INTEGER,
  seats INTEGER
);

CREATE TABLE complaint (
  id INTEGER PRIMARY KEY IDENTITY,
  order_id INTEGER,
  complaint_text TEXT,
  complaint_date DATETIME,
  complaint_status VARCHAR(MAX)
);

ALTER TABLE complaint
ADD CONSTRAINT FK_complaint_order
FOREIGN KEY (order_id) REFERENCES [order](id);

ALTER TABLE [order]
ADD CONSTRAINT FK_order_table
FOREIGN KEY (table_id) REFERENCES [table](id);

ALTER TABLE [order]
ADD CONSTRAINT FK_order_employees
FOREIGN KEY (employee_id) REFERENCES employees(id);

ALTER TABLE order_details
ADD CONSTRAINT FK_order_details_order
FOREIGN KEY (order_id) REFERENCES [order](id);

ALTER TABLE order_details
ADD CONSTRAINT FK_order_details_cocktail
FOREIGN KEY (cocktail_id) REFERENCES cocktail(id);

ALTER TABLE payment
ADD CONSTRAINT FK_payment_order
FOREIGN KEY (order_id) REFERENCES [order](id);

ALTER TABLE payment
ADD CONSTRAINT FK_payment_payment_method
FOREIGN KEY (payment_method_id) REFERENCES payment_method(id);

ALTER TABLE rating
ADD CONSTRAINT FK_rating_cocktail
FOREIGN KEY (cocktail_id) REFERENCES cocktail(id);

ALTER TABLE cocktail
ADD CONSTRAINT FK_cocktail_category
FOREIGN KEY (category_id) REFERENCES category(id);

ALTER TABLE cocktail_ingredients
ADD CONSTRAINT FK_cocktail_ingredients_cocktail
FOREIGN KEY (cocktail_id) REFERENCES cocktail(id);

ALTER TABLE cocktail_ingredients
ADD CONSTRAINT FK_cocktail_ingredients_ingredients
FOREIGN KEY (ingredient_id) REFERENCES ingredients(id);

ALTER TABLE cocktail
ADD name VARCHAR(255);

