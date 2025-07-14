"""
Модуль для работы с ККТ Штрих-М через драйвер AddIn.DrvFR (COM).
Требует установленного драйвера и библиотеки pywin32.
"""
import win32com.client
from typing import List, Dict

# Таблицы для справки
TAX1_MAP = {
    0: "БЕЗ НДС",
    1: "НДС 20%",
    2: "НДС 10%",
    3: "НДС 0%",
    4: "БЕЗ НДС",
    5: "НДС 20/120",
    6: "НДС 10/110",
    7: "НДС 5%",
    8: "НДС 7%",
    9: "НДС 5/105",
    10: "НДС 7/107",
}

TAXTYPE_MAP = {
    1: "ОСН",
    2: "УСН доход",
    4: "УСН доход-расход",
    8: "ЕНВД",
    16: "ЕСХН",
    32: "Патент",
}

class ShtrihKKT:
    def __init__(self, com_port=1, baud_rate=5, password=30):
        self.fr = win32com.client.Dispatch('AddIn.DrvFR')
        self.fr.Password = password
        self.fr.ComNumber = com_port
        self.fr.BaudRate = baud_rate
        self.fr.Connect()

    def print_text(self, text: str):
        self.fr.StringForPrinting = text
        self.fr.PrintString()

    def print_qr(self, qr_data: str):
        self.fr.BarcodeType = 3  # QR-код
        self.fr.BarCode = qr_data
        self.fr.BarcodeStartBlockNumber = 0
        self.fr.BarcodeParameter1 = 0  # версия - авто
        self.fr.BarcodeParameter1 = 4  # размер точки
        self.fr.BarcodeParameter1 = 3  # уровень коррекции ошибок
        self.fr.LoadAndPrint2DBarcode()
        self.fr.WaitForPrinting()
        self.fr.StringQuantity = 10
        self.fr.FeedDocument()
        self.fr.CutType = 2
        self.fr.CutCheck()

    def print_check(self, cashier: str, tax_type: int, items: List[Dict]):
        """
        cashier: ФИО кассира
        tax_type: система налогообложения (десятичное число, см. TAXTYPE_MAP)
        items: список товаров, каждый — dict:
            {
                "name": str,
                "price": int,   # в копейках
                "qty": float,
                "sum": int,     # в копейках
                "tax1": int     # ставка НДС
            }
        """
        # Установить ФИО кассира
        self.fr.TagNumber = 1021
        self.fr.TagType = 7
        self.fr.TagValueStr = cashier
        self.fr.FNSendTag()
        # Установить систему налогообложения
        self.fr.TaxType = tax_type
        # Открыть чек
        self.fr.CheckType = 0  # 0 - продажа
        for item in items:
            self.fr.StringForPrinting = item["name"]
            self.fr.Quantity = item["qty"]
            self.fr.Price = item["price"]
            self.fr.Department = 1
            self.fr.Tax1 = item["tax1"]
            self.fr.PaymentTypeSign = 4
            self.fr.PaymentItemSign = 1
            self.fr.FNOperation()
        # Подытог
        self.fr.CheckSubTotal()
        # Оплата (наличные и безналичные)
        total_cash = sum(i["sum"] for i in items if i.get("pay_type", "cash") == "cash")
        total_card = sum(i["sum"] for i in items if i.get("pay_type", "cash") == "card")
        self.fr.Summ1 = total_cash
        self.fr.Summ2 = total_card
        self.fr.FNCloseCheckEx()

# Пример использования
if __name__ == "__main__":
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