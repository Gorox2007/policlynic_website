import sys

def check_file_encoding(filename):
    try:
        with open(filename, 'rb') as f:
            content = f.read()
            
        # Проверяем BOM (Byte Order Mark)
        if content.startswith(b'\xef\xbb\xbf'):
            print("⚠️  Файл содержит BOM (UTF-8 with BOM)")
            return False
            
        # Пробуем декодировать как UTF-8
        content.decode('utf-8')
        print("✅ Файл в корректной кодировке UTF-8")
        return True
        
    except UnicodeDecodeError as e:
        print(f"❌ Ошибка кодировки: {e}")
        print(f"Проблемный байт: 0x{content[e.start]:02x} в позиции {e.start}")
        return False

if __name__ == "__main__":
    check_file_encoding("polyclinic/settings.py")