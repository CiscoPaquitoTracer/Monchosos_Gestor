import 'package:flutter_test/flutter_test.dart';
import 'package:monchosos_gestor/datos/errores.dart';
import 'package:monchosos_gestor/datos/menu/armar_renglon.dart';
import 'package:monchosos_gestor/datos/menu/menu.dart';
import 'package:monchosos_gestor/datos/pedidos/pedido.dart';

void main() {
  group('Menú', () {
    test('menú completo igual que el documento', () {
      expect(Menu.productos.length, 35);
      expect(Menu.productos.map((p) => p.id).toSet().length, 35);
      expect(Menu.deCategoria(CategoriaMenu.burgers).length, 7);
      expect(Menu.deCategoria(CategoriaMenu.doggos).length, 6);
      expect(Menu.deCategoria(CategoriaMenu.combos).length, 4);
      expect(Menu.producto('combo-solitario').precio, 16000);
      expect(Menu.producto('boneless').variante('boneless-10')!.precio, 13000);
      expect(
        Menu.deCategoria(CategoriaMenu.burgers).every((p) => p.incluyePapas),
        isTrue,
      );
    });

    test('todas las opciones de combo existen', () {
      final opciones = Menu.productos
          .where((p) => p.esCombo)
          .expand((p) => p.grupos)
          .expand((g) => g.opciones);
      for (final op in opciones) {
        final p = Menu.productoONull(op.productoId);
        expect(p, isNotNull, reason: 'No existe ${op.productoId}');
        if (op.varianteId != null) {
          expect(p!.variante(op.varianteId), isNotNull);
        }
      }
    });

    test('nombres sin ambigüedad', () {
      expect(
        Menu.nombreCompleto(Menu.producto('burger-junior')),
        'Burger Junior',
      );
      expect(
        Menu.nombreCompleto(Menu.producto('doggo-junior')),
        'Doggo Junior',
      );
      expect(
        Menu.nombreCompleto(Menu.producto('burger-hula-hula')),
        'Hula Hula',
      );
      expect(
        Menu.nombreCompleto(Menu.producto('aderezo-2')),
        'Aderezo Hula Hula',
      );
      final nombres = Menu.productos.map(Menu.nombreCompleto).toList();
      expect(nombres.toSet().length, nombres.length);
    });

    test('precios de Supabase reemplazan a los de respaldo', () {
      addTearDown(() => Menu.actualizar(const []));
      Menu.actualizar(const [
        PrecioDb(
          id: 10,
          categoriaDb: 'Burgers',
          nombre: 'Sweet Bacon',
          precio: 9900,
          activo: true,
        ),
        PrecioDb(
          id: 11,
          categoriaDb: 'Doggos Jumbo',
          nombre: 'Junior',
          precio: 4000,
          activo: false,
        ),
        PrecioDb(
          id: 12,
          categoriaDb: 'Alitas',
          nombre: 'Alitas',
          precio: null,
          activo: true,
          variantes: [
            VarianteDb(id: 20, nombre: '5 piezas', precio: 8000, activo: true),
            VarianteDb(
              id: 21,
              nombre: '10 piezas',
              precio: 15000,
              activo: false,
            ),
          ],
        ),
      ]);
      final sweet = Menu.producto('burger-sweet-bacon');
      expect(sweet.precio, 9900);
      expect(sweet.dbId, 10);
      expect(armarRenglon(sweet).precioUnitario, 9900);
      // "Junior" de Doggos no se confunde con el de Burgers.
      expect(Menu.producto('doggo-junior').activo, isFalse);
      expect(Menu.producto('burger-junior').precio, 7500);
      expect(Menu.producto('burger-junior').activo, isTrue);

      final alitas = Menu.producto('alitas');
      expect(alitas.variantesActivas.map((v) => v.id), ['alitas-5']);
      expect(alitas.precioDesde, 8000);
      expect(alitas.variante('alitas-10')!.precio, 15000);
    });

    test('sin datos de Supabase se usa el respaldo', () {
      Menu.actualizar(const []);
      expect(Menu.producto('burger-sweet-bacon').precio, 9000);
    });

    test('solo se ofrecen opciones de combo disponibles', () {
      addTearDown(() => Menu.actualizar(const []));
      expect(
        Menu.opcionDisponible(const OpcionCombo('boneless', 'boneless-5')),
        isTrue,
      );
      Menu.actualizar(const [
        PrecioDb(
          id: 1,
          categoriaDb: 'Boneless',
          nombre: 'Boneless',
          precio: null,
          activo: true,
          variantes: [
            VarianteDb(id: 2, nombre: '5 piezas', precio: 7000, activo: false),
          ],
        ),
      ]);
      expect(
        Menu.opcionDisponible(const OpcionCombo('boneless', 'boneless-5')),
        isFalse,
      );
    });
  });

  group('Armar renglón', () {
    test('producto simple', () {
      final r = armarRenglon(
        Menu.producto('burger-sweet-bacon'),
        cantidad: 2,
        notas: ' sin cebolla ',
      );
      expect(r.precioUnitario, 9000);
      expect(r.subtotal, 18000);
      expect(r.notas, 'sin cebolla');
    });

    test('alitas exigen tamaño y sabor', () {
      final alitas = Menu.producto('alitas');
      final error = throwsA(isA<ErrorValidacion>());
      expect(() => armarRenglon(alitas), error);
      expect(() => armarRenglon(alitas, varianteId: 'alitas-10'), error);
      final r = armarRenglon(alitas, varianteId: 'alitas-10', sabor: 'BBQ');
      expect(r.precioUnitario, 14000);
      expect(r.variante, '10 piezas');
      expect(r.sabor, 'BBQ');
    });

    test('combo incompleto falla y completo arma componentes', () {
      final desmadre = Menu.producto('combo-desmadre');
      expect(
        () =>
            armarRenglon(desmadre, elecciones: [null, null, null, null, null]),
        throwsA(isA<ErrorValidacion>()),
      );
      final r = armarRenglon(
        desmadre,
        elecciones: const [
          Eleccion(OpcionCombo('burger-hula-hula')),
          Eleccion(OpcionCombo('burger-bonchosa')),
          Eleccion(OpcionCombo('papas-criminales')),
          Eleccion(OpcionCombo('refresco-coca')),
          Eleccion(OpcionCombo('refresco-jarritos')),
        ],
      );
      expect(r.precioUnitario, 32500);
      expect(
        r.componentes,
        'Hula Hula, Bonchosa, Papas Criminales, Coca Cola 600 ml, Jarritos 600 ml',
      );
    });

    test('combo rechaza opción no permitida y exige sabor', () {
      expect(
        () => armarRenglon(
          Menu.producto('combo-desmadre'),
          elecciones: const [
            Eleccion(OpcionCombo('burger-glotona')),
            Eleccion(OpcionCombo('burger-bonchosa')),
            Eleccion(OpcionCombo('papas-criminales')),
            Eleccion(OpcionCombo('refresco-coca')),
            Eleccion(OpcionCombo('refresco-coca')),
          ],
        ),
        throwsA(isA<ErrorValidacion>()),
      );
      final bajon = Menu.producto('combo-bajon');
      const sinSabor = [
        Eleccion(OpcionCombo('boneless', 'boneless-10')),
        Eleccion(OpcionCombo('papas-junior')),
        Eleccion(OpcionCombo('aderezo-1')),
        Eleccion(OpcionCombo('aderezo-3')),
      ];
      expect(
        () => armarRenglon(bajon, elecciones: sinSabor),
        throwsA(isA<ErrorValidacion>()),
      );
      final conSabor = [sinSabor[0].conSabor('Parmesano'), ...sinSabor.skip(1)];
      final r = armarRenglon(bajon, elecciones: conSabor);
      expect(
        r.componentes,
        'Boneless 10 piezas (Parmesano), Papas Junior, Aderezo De la casa, Aderezo Cheddar',
      );
    });

    test('el renglón lleva los nombres de Supabase', () {
      final r = armarRenglon(
        Menu.producto('combo-pandora'),
        elecciones: const [
          Eleccion(OpcionCombo('burger-toxica')),
          Eleccion(OpcionCombo('burger-junior')),
          Eleccion(OpcionCombo('doggo-callejero')),
          Eleccion(OpcionCombo('doggo-pica-pica')),
          Eleccion(OpcionCombo('alitas', 'alitas-5'), 'BBQ'),
          Eleccion(OpcionCombo('boneless', 'boneless-5'), 'Parmesano'),
        ],
      );
      expect((r.categoriaDb, r.productoDb), ('Combos', 'Caja de Pandora'));
      expect(r.partes[1], const Parte('Burgers', 'Junior'));
      expect(r.partes[3], const Parte('Doggos Jumbo', 'Pica Pica'));
      expect(r.partes[4], const Parte('Alitas', 'Alitas', '5 piezas', 'BBQ'));
      expect(CategoriaMenu.values.map((c) => c.db).toSet(), {
        'Burgers',
        'Doggos Jumbo',
        'Alitas',
        'Boneless',
        'Papas',
        'Combos',
        'Aderezos Extra',
        'Refrescos',
      });
      expect(
        Menu.porNombreDb('Aderezos Extra', 'Hula Hula'),
        same(Menu.producto('aderezo-2')),
      );
    });

    test('un renglón igual suma la cantidad en lugar de duplicarse', () {
      final junior = armarRenglon(Menu.producto('burger-junior'));
      var lista = agregarRenglon(const [], junior);
      lista = agregarRenglon(lista, junior.copyWith(cantidad: 2));
      expect(lista.length, 1);
      expect(lista.single.cantidad, 3);
      lista = agregarRenglon(lista, junior.copyWith(notas: 'sin cebolla'));
      expect(lista.length, 2);
    });
  });
}
