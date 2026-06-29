import os
import re

def clean_codebase(root_dir):
    # Simple string replacements
    replacements = {
        '<<': '<',
        '>>': '>',
        'boolbool': 'bool',
        'voidvoid': 'void',
        'StringString': 'String',
        'MapMap': 'Map',
        'AuthAuthService': 'AuthService',
        'AuthStateAuthStateNotifier': 'AuthStateNotifier',
        'flutter_riderpod.dart': 'flutter_riverpod.dart'
    }

    # Regex replacements for common broken generics
    regex_replacements = [
        (r'Map<String,\s*dynamic\s*(?=[^>])', 'Map<String, dynamic>'),
        (r'List<Map<String,\s*dynamic\s*(?=[^>])', 'List<Map<String, dynamic>>'),
        (r'List<Map<String,\s*String\s*(?=[^>])', 'List<Map<String, String>>'),
        (r'List<LocalizationsDelegate<dynamic\s*(?=[^>])', 'List<LocalizationsDelegate<dynamic>>'),
    ]

    for root, dirs, files in os.walk(root_dir):
        for file in files:
            if file.endswith('.dart'):
                file_path = os.path.join(root, file)
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()

                new_content = content

                # Apply simple replacements
                for old, new in replacements.items():
                    new_content = new_content.replace(old, new)

                # Apply regex replacements
                for pattern, replacement in regex_replacements:
                    new_content = re.sub(pattern, replacement, new_content)

                if new_content != content:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    print(f"Cleaned: {file_path}")

if __name__ == "__main__":
    root_path = r'C:\Users\sanja\OneDrive\Desktop\IGRIS_AGENT\mobile_app\igris_mobile\lib'
    clean_codebase(root_path)
