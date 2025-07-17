from shtrih_kkt import ShtrihKKT, ShtrihKKTError

if __name__ == "__main__":
    try:
        kkt = ShtrihKKT(com_port=1, baud_rate=5, password=30)
        kkt.print_text("Добро пожаловать!")
        kkt.print_qr("https://example.com")
        # Обычный чек
        kkt.print_check(
            cashier="Иванов Иван",
            tax_type=2,  # УСН доход
            items=[
                {"name": "Товар 1", "price": 10000, "qty": 2, "sum": 20000, "tax1": 1},
                {"name": "Товар 2", "price": 5000, "qty": 1, "sum": 5000, "tax1": 0},
            ],
            cash_sum=20000,   # 200 руб. наличными
            card_sum=5000     # 50 руб. по карте
        )
        # Возвратный чек
        kkt.print_check(
            cashier="Петров Петр",
            tax_type=2,
            items=[
                {"name": "Возврат товара", "price": 15000, "qty": 1, "sum": 15000, "tax1": 1},
            ],
            is_return=True,
            cash_sum=0,
            card_sum=15000    # 150 руб. возврат по карте
        )
    except ShtrihKKTError as e:
        print(f"Ошибка ККТ: {e}")
    except Exception as e:
        print(f"Другая ошибка: {e}")
