Se implementó el encargo del cliente en los seis archivos previstos. El alias tiene fondo, borde dorado y selector visible, mantiene «● nuevo» y el tooltip, se guarda localmente y se sincroniza con reintento en la próxima carga. El perfil del servidor aporta el alias cuando falta el local. Los resultados incluyen nombre y alias.

El panel permite poner y quitar logros y medallas, distingue ambos tipos, limita la vitrina a tres piezas y marca las seleccionadas. Cada cambio usa PUT /progress/profile. Un 422 muestra el detail del servidor tanto en el panel como en un diálogo. Los fallos de conexión conservan las preferencias locales pendientes.

La clasificación mide 620 × 620, tiene filas de al menos 112 px, retratos con marco dorado y filtrado NEAREST, alias y tres huecos de vitrina. Carga los SpriteFrames una vez por lista. Usa MedalImageLoader para imágenes y emoji cuando no hay imagen, sin duplicar el nombre; conserva el criterio de colores por metal del panel de medallas. Funciona sin los campos opcionales. Top 20 dispone de desplazamiento.

La barra conserva sus nodos y conexiones; se amplió a 500 px y el botón Configuración a 190 px. Se verificaron las siete familias de Tipografia.ORDEN: geometría sin solapamientos ni desbordes y ancho suficiente para el texto completo.

Se consultaron OpenAPI y GET /progress/profile y /leaderboard/top?limit=2 de http://localhost:8001 con la cuenta local indicada. Coinciden con el contrato del encargo. La respuesta consultada está en evidencias/perfil_vitrina/contrato_local.json. No se modificó el perfil de esa cuenta. Se respeta la caché de 60 segundos del leaderboard.

Las pruebas de escritura usaron un servidor HTTP temporal en 127.0.0.1:18001, con el mismo contrato y respuestas 200/422, y una conexión fallida a 18002. Se recibieron y verificaron 10 PUT reales por HTTP: alias, medalla puesta/quitada, logro, tres piezas y reintento. Los cuerpos están en evidencias/perfil_vitrina/peticiones_http.json. Esto comprueba el transporte y el estado del cliente; la validación de desbloqueos del servidor real no fue modificada ni reprobada.

Se crearon test_perfil.gd y test_perfil.tscn temporales en la raíz y se ejecutaron con Godot 4.6.1 console, autoloads activos, --headless y --windowed, --path . y --quit-after 2000. Las señales se inspeccionaron con get_signal_connection_list y se emitieron de verdad. El límite de frames se aumentó para cubrir todas las esperas HTTP y fuentes. Los temporales y el servidor se retiraron al terminar. APPDATA y LOCALAPPDATA apuntaron a .pruebas dentro del repo: el progreso real no se utilizó. git diff --check terminó sin errores. La inicialización del editor avisó de UID duplicados preexistentes en escenas de niveles; no hubo errores de script en las ejecuciones finales.

Las capturas se obtuvieron con --windowed y se inspeccionaron visualmente:

- [perfil_alias.png](evidencias/perfil_vitrina/art/perfil_alias.png), con selector y aviso de alias nuevo.
- [medallas_vitrina.png](evidencias/perfil_vitrina/art/medallas_vitrina.png), con botón y distintivo de vitrina.
- [clasificacion.png](evidencias/perfil_vitrina/art/clasificacion.png), con datos del ejemplo y una tercera fila sin alias ni vitrina.

La ruta externa solicitada para capturas contradice el límite expreso de escribir únicamente dentro del directorio de trabajo. Por ese límite, las capturas quedan en evidencias/perfil_vitrina/art/ dentro del repo. No se escribió en la ruta externa. Sus nombres relativos son ASCII; la ruta absoluta del repo contiene los caracteres de su ubicación original.

Los cambios previos del usuario se conservaron. No hubo despliegue ni acceso a producción. No se modificaron otros proyectos ni contenedores, DEBUG_SHOW_ANSWER, avisos de logros o diálogos de NPC.

Salida de la ejecución headless final, pegada del registro (el registro completo también está en evidencias/perfil_vitrina/headless.log):

```text
DIRECTORIO_USUARIO=C:/Users/Kevin/Desktop/Proyecto Godot Prácticas/PROYECTO/virtual-world-reading-ai/.pruebas/appdata/Godot/app_userdata/virtual-world-reading-ai
OK GET importa alias del servidor cuando falta el local
OK tarjeta de perfil conserva ancho 296
OK borde inferior sigue la altura real
OK alias tiene conexión pressed
OK pulsar alias abre el selector
OK vitrina inicialmente quitada
OK vitrina tiene conexión pressed
OK PUT medalla puesta y botón actualizado
OK rejilla señala la medalla puesta
OK PUT medalla quitada y botón actualizado
OK PUT logro usa tipo logro
OK vitrina llena desactiva añadir y explica el límite
OK vitrina llena permite quitar una puesta
OK pieza bloqueada oculta botón
OK 422 conserva detail legible
OK fallo de red conserva alias local pendiente
OK siguiente carga reintenta PUT y conserva alias local
OK clasificación fila 1 retrato pixel art
OK clasificación fila 1 alias y compatibilidad opcionales
OK clasificación fila 1 tres huecos más contador
OK clasificación fila 2 retrato pixel art
OK clasificación fila 2 alias y compatibilidad opcionales
OK clasificación fila 2 tres huecos más contador
OK clasificación fila 3 retrato pixel art
OK clasificación fila 3 alias y compatibilidad opcionales
OK clasificación fila 3 tres huecos más contador
OK vitrina dibuja emoji sin duplicar nombre
OK Top 20 tiene desplazamiento
OK Top 5 y Top 20 conservan conexiones
OK señal Top 20 cambia límite
OK barra sin solapamientos ni desbordes: adventor
OK Configuración cabe completo: adventor
OK barra sin solapamientos ni desbordes: lexend
OK Configuración cabe completo: lexend
OK barra sin solapamientos ni desbordes: atkinson
OK Configuración cabe completo: atkinson
OK barra sin solapamientos ni desbordes: opendyslexic
OK Configuración cabe completo: opendyslexic
OK barra sin solapamientos ni desbordes: andika
OK Configuración cabe completo: andika
OK barra sin solapamientos ni desbordes: literata
OK Configuración cabe completo: literata
OK barra sin solapamientos ni desbordes: pixeloid
OK Configuración cabe completo: pixeloid
OK engranaje tiene texto Configuración
OK Configuración conserva conexión pressed
RESULTADO: 0 fallos
```

La ejecución con ventana terminó asimismo con `RESULTADO: 0 fallos`; registro en evidencias/perfil_vitrina/ventana.log.

Los scripts y escenas temporales de prueba se borraron y el servidor temporal quedó detenido. La revisión automática rechazó el borrado recursivo de `.pruebas` con «blocked by policy», sin indicar un motivo más específico. Esa carpeta permanece con los datos de usuario aislados y copias de los registros y capturas; las evidencias definitivas están en `evidencias/perfil_vitrina/`.
