extends SceneTree

func _init():
	var emoji_f: Font = load("res://fonts/NotoColorEmoji.ttf")
	
	# When SceneManager boots, it can find all theme fallback fonts and append emoji_f to their fallbacks!
	var sample_lbl := Label.new()
	var default_theme_font := sample_lbl.get_theme_font("font")
	print("default_theme_font:", default_theme_font)
	if default_theme_font is FontFile and not emoji_f in default_theme_font.fallbacks:
		default_theme_font.fallbacks.append(emoji_f)
	
	if ThemeDB.fallback_font is FontFile and not emoji_f in ThemeDB.fallback_font.fallbacks:
		ThemeDB.fallback_font.fallbacks.append(emoji_f)
		
	var scn: PackedScene = load("res://scenes/UI/login_screen.tscn")
	var inst = scn.instantiate()
	root.add_child(inst)
	
	var title_icon: Label = inst.find_child("TitleIcon", true, false)
	var f := title_icon.get_theme_font("font")
	print("TitleIcon font:", f)
	print("TitleIcon font has 📖:", f.has_char(0x1f4d6))
	
	var email_lbl: Label = inst.find_child("EmailLabel", true, false)
	var f_email := email_lbl.get_theme_font("font")
	print("EmailLabel font has ✉️:", f_email.has_char(0x2709))
	
	var pass_lbl: Label = inst.find_child("PasswordLabel", true, false)
	var f_pass := pass_lbl.get_theme_font("font")
	print("PasswordLabel font has 🔒:", f_pass.has_char(0x1f512))
	
	quit()
