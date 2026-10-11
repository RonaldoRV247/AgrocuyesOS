import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/demo/semilla.dart';
import 'core/theme/campo_theme.dart';
import 'core/utils/tiempo.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/auth/data/auth_repositorio.dart';
import 'features/crianza/presentation/vista_pozas.dart';
import 'features/sync/application/sync_providers.dart';
import 'features/sync/application/sync_worker.dart';
import 'features/tareas/presentation/cuadrilla_tareas.dart';
import 'shared/data/local/app_database.dart';
import 'shared/di/inyeccion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Una mano, de pie, junto a la poza. Rotar la pantalla no aporta nada y
  // cambia el tamano de los botones bajo el pulgar.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);

  // Se abre ANTES de pintar la primera pantalla y se inyecta al scope: sembrar
  // dentro de un FutureBuilder dejaria la cuadrilla vacia medio segundo, y un
  // productor que ve "sin tareas" cree que perdio su dia.
  final AppDatabase db = AppDatabase(conectar());
  final RelojCampo reloj = RelojCampo();
  await sembrarSiVacio(db, reloj);

  runApp(
    ProviderScope(
      overrides: <Override>[
        // overrideWithValue no ejecuta el cuerpo del provider, asi que el
        // `ref.onDispose(db.close)` original no corre: la conexion la cierra el
        // proceso al morir. Se mantiene una sola instancia para toda la app.
        baseDeDatosProvider.overrideWithValue(db),
        relojProvider.overrideWithValue(reloj),
      ],
      child: const AgrocuyesApp(),
    ),
  );
}

class AgrocuyesApp extends ConsumerWidget {
  const AgrocuyesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instalar los disparadores del sync (conectividad + timer + intento al
    // arrancar). Se resuelve aqui porque es lo unico "en segundo plano" que
    // existe en la app: no hay isolates ni workers propios.
    ref.watch(sincronizacionAutomaticaProvider);

    return MaterialApp(
      title: 'Agrocuyes',
      debugShowCheckedModeBanner: false,
      theme: construirTemaCampo(),
      home: const PantallaInicio(),
    );
  }
}

class PantallaInicio extends ConsumerStatefulWidget {
  const PantallaInicio({super.key});

  @override
  ConsumerState<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends ConsumerState<PantallaInicio> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final Sesion? sesion = ref.watch(sesionProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: CampoColores.fondo,
        title: const Text('Agrocuyes', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: const <Widget>[ChipPendientesSync(), ChipCuenta()],
      ),
      body: Column(
        children: <Widget>[
          if (sesion == null) const _AvisoSinCuenta(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const <Widget>[CuadrillaTareas(), VistaPozas()],
            ),
          ),
        ],
      ),
      // Navegacion de pulgar: dos destinos, 84dp de alto, iconos de 32.
      bottomNavigationBar: NavigationBar(
        height: 84,
        selectedIndex: _tab,
        backgroundColor: CampoColores.superficie,
        indicatorColor: CampoColores.accion,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (int i) => setState(() => _tab = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.agriculture_rounded, size: 32),
            selectedIcon: Icon(Icons.agriculture_rounded, size: 32),
            label: 'Tareas',
          ),
          NavigationDestination(
            icon: Icon(Icons.pets_rounded, size: 32),
            selectedIcon: Icon(Icons.pets_rounded, size: 32),
            label: 'Pozas',
          ),
        ],
      ),
    );
  }
}

/// Los cambios locales se guardan igual sin sesion: lo que no hay es forma de
/// atribuirlos ni de subirlos cuando el backend exija JWT. El aviso dice la
/// consecuencia real, no "inicie sesion para continuar".
class _AvisoSinCuenta extends ConsumerWidget {
  const _AvisoSinCuenta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: CampoColores.pendienteDeSync,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: <Widget>[
            const Icon(Icons.account_circle_rounded, color: Color(0xFF06130A)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Sin cuenta Google: los registros quedan en este telefono.',
                style: TextStyle(color: Color(0xFF06130A), fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(sesionProvider.notifier).iniciarConGoogle(),
              child: const Text(
                'CONECTAR',
                style: TextStyle(color: Color(0xFF06130A), fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Badge de cola: cuantos cambios esperan senal. Tocarlo fuerza una subida, que
/// es el unico control explícito que se le deja al usuario sobre el sync.
class ChipPendientesSync extends ConsumerWidget {
  const ChipPendientesSync({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int pendientes = ref.watch(cambiosPendientesProvider).valueOrNull ?? 0;
    final bool hayRed = ref.watch(conectividadProvider).valueOrNull ?? false;

    return InkWell(
      onTap: () async {
        final ResultadoSync r = await ref.read(syncWorkerProvider).sincronizarAhora();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              r.falloDeRed
                  ? 'Sin senal: se subira cuando vuelva (${r.enviados} en cola)'
                  : r.enviados == 0
                      ? 'Todo sincronizado'
                      : '${r.aceptados} subido(s), ${r.descartados} actualizado(s) desde el servidor',
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: <Widget>[
            Icon(
              pendientes == 0 ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded,
              color: pendientes == 0
                  ? CampoColores.accion
                  : (hayRed ? CampoColores.pendienteDeSync : CampoColores.alerta),
              size: 26,
            ),
            if (pendientes > 0) ...<Widget>[
              const SizedBox(width: 4),
              Text('$pendientes', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ],
        ),
      ),
    );
  }
}

class ChipCuenta extends ConsumerWidget {
  const ChipCuenta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Sesion? sesion = ref.watch(sesionProvider).valueOrNull;
    if (sesion == null) return const SizedBox(width: 24);

    final String nombre = sesion.nombre.split(' ').first;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () => ref.read(sesionProvider.notifier).cerrarSesion(),
        child: Row(
          children: <Widget>[
            const Icon(Icons.person_rounded, size: 24),
            const SizedBox(width: 4),
            Text(nombre, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
