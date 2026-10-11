/// Configuracion de entorno. `--dart-define` en vez de archivos por flavor:
/// en campo se prueba contra el server del tecnico en una LAN del pueblo y eso
/// no amerita un build nuevo.
const String kBaseUrl = String.fromEnvironment(
  'AGROCUYES_API',
  defaultValue: 'http://10.0.2.2:8080', // emulator Android -> localhost del host
);

/// Margen de renovacion: el access token se renueva 2 minutos antes de vencer,
/// para que una subida de lote no muera a mitad por un token recién caducado.
const int kMargenRefrescoMillis = 120000;
