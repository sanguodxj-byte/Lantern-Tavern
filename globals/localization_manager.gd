extends Node

const TRANSLATIONS_CSV := "res://scenes/ui/localization/translations.csv"

func _ready() -> void:
	_load_translations()

func _load_translations() -> void:
	if not ResourceLoader.exists(TRANSLATIONS_CSV):
		push_error("Localization: translation CSV not found at ", TRANSLATIONS_CSV)
		return

	var csv_file = FileAccess.open(TRANSLATIONS_CSV, FileAccess.READ)
	if not csv_file:
		push_error("Localization: failed to open translation CSV")
		return

	# Read CSV header to get locale columns
	var header_line = csv_file.get_line()
	var headers = _parse_csv_line(header_line)
	
	# Column 0 = "key", columns 1..N are locale codes
	var locale_columns = headers.slice(1)
	
	# Create a Translation for each locale
	var translations_by_locale = {}
	for locale in locale_columns:
		var translation = Translation.new()
		translation.locale = locale
		translations_by_locale[locale] = translation

	# Parse each row: key, en_value, zh_value, ...
	while not csv_file.eof_reached():
		var line = csv_file.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
			
		var fields = _parse_csv_line(line)
		if fields.size() < 3:
			continue
			
		var msg_key = fields[0]
		for i in range(locale_columns.size()):
			var locale = locale_columns[i]
			if i + 1 < fields.size() and not fields[i + 1].is_empty():
				var translation = translations_by_locale[locale]
				translation.add_message(msg_key, fields[i + 1])

	# Register all translations
	for locale in translations_by_locale:
		TranslationServer.add_translation(translations_by_locale[locale])

	print("Localization: loaded %d languages (%s)" % [locale_columns.size(), ", ".join(locale_columns)])

func _parse_csv_line(line: String) -> PackedStringArray:
	# Simple CSV parser that handles quoted fields
	var result = PackedStringArray()
	var current = ""
	var in_quotes = false
	var i = 0
	while i < line.length():
		var c = line[i]
		if c == '"':
			if in_quotes and i + 1 < line.length() and line[i + 1] == '"':
				current += '"'
				i += 1
			else:
				in_quotes = not in_quotes
		elif c == ',' and not in_quotes:
			result.append(current.strip_edges())
			current = ""
		else:
			current += c
		i += 1
	result.append(current.strip_edges())
	return result
