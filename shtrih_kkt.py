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

class ShtrihKKTError(Exception):
    """Исключение для ошибок работы с ККТ Штрих."""

class ShtrihKKT:
    def __init__(self, com_port=1, baud_rate=5, password=30):
        try:
            self.fr = win32com.client.Dispatch('AddIn.DrvFR')
        except Exception as e:
            raise ShtrihKKTError(
                "Ошибка создания COM-объекта 'AddIn.DrvFR'.\n"
                "Проверьте, установлен ли драйвер ККТ Штрих-М и зарегистрирован ли COM-компонент.\n"
                "ВАЖНО: Разрядность Python и драйвера ККТ должна совпадать (оба x86 или оба x64).\n"
                f"Текст ошибки: {e}"
            )
        try:
            self.fr.Password = password
            self.fr.ComNumber = com_port
            self.fr.BaudRate = baud_rate
            self.fr.Connect()
        except Exception as e:
            raise ShtrihKKTError(f"Ошибка инициализации ККТ: {e}")

    def print_text(self, text: str):
        try:
            self.fr.StringForPrinting = text
            self.fr.PrintString()
        except Exception as e:
            raise ShtrihKKTError(f"Ошибка печати текста: {e}")

    def print_qr(self, qr_data: str):
        try:
            self.fr.BarcodeType = 3
            self.fr.BarCode = qr_data
            self.fr.BarcodeStartBlockNumber = 0
            self.fr.BarcodeParameter1 = 0
            #self.fr.BarcodeParameter2 = 4
            self.fr.BarcodeParameter3 = 3
            #self.fr.PrintBarcodeGraph()
            self.fr.LoadAndPrint2DBarcode()
            self.fr.WaitForPrinting()
            self.fr.StringQuantity = 10
            self.fr.FeedDocument()
            self.fr.CutType = 2
            self.fr.CutCheck()
        except Exception as e:
            raise ShtrihKKTError(f"Ошибка печати QR-кода: {e}")
        
    def print_qr2(self, qr_data: str):
        try:
            self.fr.BarcodeType = 3
            self.fr.BarCode = qr_data
            self.fr.LineNumber = 200
            self.fr.BarWidth = 200
            self.fr.BarcodeAlignment = 0            
            #self.fr.BarcodeParameter1 = 0
            #self.fr.BarcodeParameter2 = 4
            #self.fr.BarcodeParameter3 = 3
            self.fr.PrintBarcodeGraph()
            #self.fr.LoadAndPrint2DBarcode()
            self.fr.WaitForPrinting()
            self.fr.StringQuantity = 10
            self.fr.FeedDocument()
            self.fr.CutType = 2
            self.fr.CutCheck()
        except Exception as e:
            raise ShtrihKKTError(f"Ошибка печати QR-кода: {e}")        

    def print_check(self, cashier: str, tax_type: int, items: List[Dict], is_return: bool = False):
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
        is_return: если True — чек возврата (CheckType=2), иначе обычный чек (CheckType=0)
        """
        try:
        # Установить ФИО кассира
            self.fr.TagNumber = 1021
            self.fr.TagType = 7
            self.fr.TagValueStr = cashier
            self.fr.FNSendTag()
            # Установить систему налогообложения
            self.fr.TaxType = tax_type
            # Открыть чек
            self.fr.CheckType = 2 if is_return else 0
            for item in items:
                try:
                    self.fr.StringForPrinting = item["name"]
                    self.fr.Quantity = item["qty"]
                    self.fr.Price = item["price"]
                    self.fr.Department = 1
                    self.fr.Tax1 = item["tax1"]
                    self.fr.PaymentTypeSign = 4
                    self.fr.PaymentItemSign = 1
                    self.fr.FNOperation()
                except Exception as e:
                    raise ShtrihKKTError(f"Ошибка печати товара: {e}")            
            # Подытог
            self.fr.CheckSubTotal()
            # Оплата (наличные и безналичные)
            total_cash = sum(i["sum"] for i in items if i.get("pay_type", "cash") == "cash")
            total_card = sum(i["sum"] for i in items if i.get("pay_type", "cash") == "card")
            self.fr.Summ1 = total_cash
            self.fr.Summ2 = total_card
            self.fr.FNCloseCheckEx()
        except Exception as e:
            raise ShtrihKKTError(f"Ошибка печати чека: {e}") 
        finally:
            self.fr.Close()