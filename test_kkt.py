from shtrih_kkt import ShtrihKKT, ShtrihKKTError

if __name__ == "__main__":
    try:
        kkt = ShtrihKKT(com_port=1, baud_rate=5, password=30)
        kkt.print_text("Добро пожаловать!")
        kkt.print_qr("https://example.com")
        kkt.print_check(
            cashier="Иванов Иван",
            tax_type=2,  # УСН доход
            items=[
                {"name": "Товар 1", "price": 10000, "qty": 2, "sum": 20000, "tax1": 1},
                {"name": "Товар 2", "price": 5000, "qty": 1, "sum": 5000, "tax1": 0},
            ]
        )
    except ShtrihKKTError as e:
        print(f"Ошибка ККТ: {e}")
    except Exception as e:
        print(f"Другая ошибка: {e}")
