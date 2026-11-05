import 'package:flutter_test/flutter_test.dart';
import 'package:monchosos_gestor/datos/errores.dart';
import 'package:monchosos_gestor/datos/inventario/insumo.dart';

void main() {
  test('formulario válido por kilo acepta coma decimal', () {
    final i = const FormularioInsumo(
      nombre: ' Jitomate ',
      cantidad: '2,5',
      stockMinimo: '1',
    ).validar();
    expect(i.nombre, 'Jitomate');
    expect(i.unidad, Unidad.kilogramo);
    expect(i.cantidad, 2.5);
  });

  test('formulario rechaza nombre vacío y números inválidos', () {
    final error = throwsA(isA<ErrorValidacion>());
    expect(
      () => const FormularioInsumo(nombre: '', cantidad: '1').validar(),
      error,
    );
    expect(
      () => const FormularioInsumo(nombre: 'Pan', cantidad: 'abc').validar(),
      error,
    );
    expect(
      () => const FormularioInsumo(nombre: 'Pan', cantidad: '-3').validar(),
      error,
    );
    expect(
      () => const FormularioInsumo(nombre: 'Pan', cantidad: 'NaN').validar(),
      error,
    );
  });

  test('las piezas deben ser enteras', () {
    const form = FormularioInsumo(
      nombre: 'Caja',
      categoria: CategoriaInsumo.desechable,
      unidad: Unidad.pieza,
    );
    expect(
      () => form.copyWith(cantidad: '1.5').validar(),
      throwsA(
        predicate(
          (e) =>
              e is ErrorValidacion &&
              e.mensaje == 'Las piezas deben ser números enteros.',
        ),
      ),
    );
    expect(form.copyWith(cantidad: '100').validar().cantidad, 100);
  });

  test('por agotarse solo si hay mínimo', () {
    const pan = Insumo(
      nombre: 'Pan',
      categoria: CategoriaInsumo.panes,
      unidad: Unidad.pieza,
      cantidad: 5,
    );
    expect(pan.bajoStock, isFalse);
    expect(pan.copyWith(stockMinimo: 10).bajoStock, isTrue);
    expect(pan.copyWith(stockMinimo: 5).bajoStock, isTrue);
  });

  test('formato de cantidades', () {
    expect(formatearCantidad(40, Unidad.pieza), '40 pz');
    expect(formatearCantidad(2.5, Unidad.kilogramo), '2.5 kg');
    expect(formatearCantidad(3, Unidad.kilogramo), '3 kg');
    expect(formatearCantidad(49.55, Unidad.kilogramo), '49.55 kg');
    expect(formatearCantidad(1.5, Unidad.litro), '1.5 L');
  });

  test('categoría desconocida se trata como Otros', () {
    expect(CategoriaInsumo.desdeDb('xyz'), CategoriaInsumo.otro);
    expect(CategoriaInsumo.values.first, CategoriaInsumo.carnes);
  });
}
