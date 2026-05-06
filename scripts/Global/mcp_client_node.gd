extends Node

# Autoload MCPClientNode
# En el futuro este nodo se comunicará asíncronamente con el MCP server
# Por ahora proporciona mocks estáticos.

func request_assistance(consulta: String) -> String:
	# Mock simple
	return "Puedo ayudarte a aclarar términos sobre la lectura actual. Esta es una respuesta generada desde el MCP Client para la consulta: " + consulta
