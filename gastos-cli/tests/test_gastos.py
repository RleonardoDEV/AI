import io
from datetime import date

import pytest

from gastos.cli import a_centimos, formato, main
from gastos.db import Almacen


@pytest.fixture
def db(tmp_path):
    return str(tmp_path / "test.db")


def run(db, *args):
    out = io.StringIO()
    code = main(["--db", db, *args], salida=out)
    return code, out.getvalue()


def test_conversion_importes():
    assert a_centimos("12,50") == 1250
    assert a_centimos("3.1") == 310
    assert formato(123456) == "1.234,56 €"
    assert formato(5) == "0,05 €"


def test_importe_invalido_falla(db):
    with pytest.raises(SystemExit):
        run(db, "anadir", "-3", "comida")


def test_anadir_y_listar(db):
    run(db, "anadir", "12,50", "Comida", "menú", "--fecha", "2026-10-01")
    run(db, "anadir", "2", "transporte", "--fecha", "2026-10-02")
    code, out = run(db, "listar", "--mes", "2026-10")
    assert code == 0
    assert "comida" in out and "transporte" in out
    assert "14,50 €" in out  # total


def test_filtros(db):
    a = Almacen(db)
    a.anadir(date(2026, 9, 30), 100, "comida")
    a.anadir(date(2026, 10, 1), 200, "comida")
    a.anadir(date(2026, 10, 1), 300, "ocio")
    assert len(a.listar(mes="2026-10")) == 2
    assert len(a.listar(categoria="COMIDA")) == 2
    assert a.resumen("2026-10") == {"ocio": 300, "comida": 200}


def test_borrar(db):
    run(db, "anadir", "5", "ocio")
    assert run(db, "borrar", "1")[0] == 0
    assert run(db, "borrar", "1")[0] == 1


def test_resumen_con_presupuesto_superado(db):
    run(db, "presupuesto", "ocio", "10")
    run(db, "anadir", "15", "ocio", "--fecha", "2026-10-05")
    _, out = run(db, "resumen", "--mes", "2026-10")
    assert "150%" in out and "SUPERADO" in out


def test_exportar_csv(db):
    run(db, "anadir", "9,99", "libros", "novela", "--fecha", "2026-10-03")
    _, out = run(db, "exportar")
    lineas = out.strip().splitlines()
    assert lineas[0] == "id,fecha,importe,categoria,descripcion"
    assert lineas[1] == "1,2026-10-03,9.99,libros,novela"


@pytest.mark.parametrize("texto", ["0", "0,001", "nan", "abc", "inf"])
def test_importes_no_validos(texto):
    import argparse

    with pytest.raises(argparse.ArgumentTypeError):
        a_centimos(texto)
