## medal_image_loader.gd
## Autoload que descarga y cachea imágenes de medallas desde la API.
## Guarda los archivos en: user://cache/medals/
extends Node

const CACHE_DIR := "user://cache/medals/"

# Diccionario para evitar descargas duplicadas de la misma medalla en paralelo
# {"achievement_id": [callback1, callback2, ...]}
var _pending_downloads: Dictionary = {}

func _ready() -> void:
	# Crear directorio de cache si no existe
	var dir := DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("cache"):
			dir.make_dir("cache")
		
		dir = DirAccess.open("user://cache/")
		if dir and not dir.dir_exists("medals"):
			dir.make_dir("medals")
	print("[MedalImageLoader] Inicializado. Cache en: %s" % CACHE_DIR)


## Carga la imagen de una medalla. 
## Si está en cache Y la URL no cambió, ejecuta el callback inmediatamente.
## Si la URL cambió o no hay cache, la descarga de la API y actualiza el cache.
func load_medal_image(achievement_id: String, image_url: String, callback: Callable) -> void:
	if image_url.is_empty():
		callback.call(null)
		return
		
	var cache_path := CACHE_DIR + achievement_id + ".png"
	var version_path := CACHE_DIR + achievement_id + ".ver"
	
	# Generar un hash simple de la URL para detectar cambios (ej. ?v=timestamp)
	var url_hash := str(image_url.hash())
	
	# 1. Verificar si está en cache local Y si la versión coincide
	if FileAccess.file_exists(cache_path) and FileAccess.file_exists(version_path):
		var stored_hash := FileAccess.get_file_as_string(version_path).strip_edges()
		if stored_hash == url_hash:
			var texture = _load_texture_from_file(cache_path)
			if texture:
				callback.call(texture)
				return
		else:
			# URL cambió — invalidar cache para forzar re-descarga
			print("[MedalImageLoader] URL cambió para medalla: %s — re-descargando" % achievement_id)
			invalidate_cache(achievement_id)
	
	# 2. Si no está en cache, descargar
	var full_url = image_url
	if not image_url.begins_with("http"):
		# Es una ruta relativa de la API
		var api_base = ApiConfig.BASE_URL
		# Reemplazar /api o similares al final para obtener la raíz
		if api_base.ends_with("/api"):
			api_base = api_base.substr(0, api_base.length() - 4)
		elif api_base.ends_with("/"):
			api_base = api_base.substr(0, api_base.length() - 1)
		
		# Si la URL de la imagen comienza con /
		if image_url.begins_with("/"):
			full_url = "%s%s" % [api_base, image_url]
		else:
			full_url = "%s/%s" % [api_base, image_url]
	
	# Si ya hay una descarga en curso para esta medalla, encolar el callback
	if _pending_downloads.has(achievement_id):
		_pending_downloads[achievement_id].append(callback)
		return
		
	_pending_downloads[achievement_id] = [callback]
	
	var http_req := HTTPRequest.new()
	add_child(http_req)
	var url_hash_to_save := str(image_url.hash())
	http_req.request_completed.connect(func(result, response_code, headers, body):
		_on_download_completed(result, response_code, body, achievement_id, cache_path, url_hash_to_save, http_req)
	)
	
	# Agregar token de autorización si es necesario
	var headers := PackedStringArray()
	if not AuthManager.auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % AuthManager.auth_token)
		
	var err := http_req.request(full_url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		push_error("[MedalImageLoader] Error al solicitar descarga de medalla: %s" % achievement_id)
		_trigger_callbacks(achievement_id, null)
		http_req.queue_free()


func _on_download_completed(result: int, response_code: int, body: PackedByteArray, achievement_id: String, cache_path: String, url_hash: String, http_req: HTTPRequest) -> void:
	http_req.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("[MedalImageLoader] Falló descarga de medalla: %s (HTTP %d)" % [achievement_id, response_code])
		_trigger_callbacks(achievement_id, null)
		return
		
	# Guardar en archivo local cache
	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	if file:
		file.store_buffer(body)
		file.close()
		
		# Guardar marcador de versión para detectar cambios futuros
		var version_path := CACHE_DIR + achievement_id + ".ver"
		var ver_file := FileAccess.open(version_path, FileAccess.WRITE)
		if ver_file:
			ver_file.store_string(url_hash)
			ver_file.close()
		
		# Cargar textura
		var texture = _load_texture_from_file(cache_path)
		_trigger_callbacks(achievement_id, texture)
		print("[MedalImageLoader] Medalla descargada y cacheada: %s" % achievement_id)
	else:
		push_error("[MedalImageLoader] No se pudo escribir archivo de cache para medalla: %s" % achievement_id)
		_trigger_callbacks(achievement_id, null)


func _load_texture_from_file(file_path: String) -> ImageTexture:
	var image := Image.new()
	var err := image.load_png_from_buffer(FileAccess.get_file_as_bytes(file_path))
	if err == OK:
		return ImageTexture.create_from_image(image)
	else:
		push_error("[MedalImageLoader] Error cargando imagen a textura: %s" % file_path)
		return null


func _trigger_callbacks(achievement_id: String, texture: Texture2D) -> void:
	if _pending_downloads.has(achievement_id):
		var callbacks: Array = _pending_downloads[achievement_id]
		_pending_downloads.erase(achievement_id)
		for callback in callbacks:
			if callback.is_valid():
				callback.call(texture)


## Invalida la imagen cacheada de una medalla específica.
## La próxima vez que se llame load_medal_image, se descargará de nuevo.
func invalidate_cache(achievement_id: String) -> void:
	var cache_path := CACHE_DIR + achievement_id + ".png"
	var version_path := CACHE_DIR + achievement_id + ".ver"
	var dir := DirAccess.open(CACHE_DIR)
	if dir:
		if FileAccess.file_exists(cache_path):
			dir.remove(achievement_id + ".png")
		if FileAccess.file_exists(version_path):
			dir.remove(achievement_id + ".ver")
		print("[MedalImageLoader] Cache invalidado para medalla: %s" % achievement_id)


## Invalida todo el cache de medallas.
## Útil cuando se detecta un cambio de session_version desde el dashboard.
func invalidate_all_cache() -> void:
	var dir := DirAccess.open(CACHE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and (file_name.ends_with(".png") or file_name.ends_with(".ver")):
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		print("[MedalImageLoader] Todo el cache de medallas invalidado")


## Invalida el cache de una medalla y la recarga inmediatamente.
## callback recibe la nueva textura (o null si falla).
func clear_and_reload(achievement_id: String, image_url: String, callback: Callable) -> void:
	invalidate_cache(achievement_id)
	load_medal_image(achievement_id, image_url, callback)
