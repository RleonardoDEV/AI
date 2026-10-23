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


# --- editar ---------------------------------------------------------------
def test_editar_solo_cambia_lo_indicado(db):
    run(db, "anadir", "5", "ocio", "cine", "--fecha", "2026-10-01")
    code, out = run(db, "editar", "1", "--importe", "7,25", "--categoria", "Cultura")
    assert code == 0 and "actualizado" in out
    (g,) = Almacen(db).listar()
    assert (g.importe, g.categoria, g.descripcion, g.fecha) == (725, "cultura", "cine", date(2026, 10, 1))


def test_editar_inexistente_o_sin_campos(db):
    assert run(db, "editar", "99", "--importe", "1")[0] == 1
    run(db, "anadir", "5", "ocio")
    assert run(db, "editar", "1")[0] == 2


# --- importar -------------------------------------------------------------
def test_exportar_e_importar_ida_y_vuelta(db, tmp_path):
    run(db, "anadir", "9,99", "libros", "novela, tapa dura", "--fecha", "2026-10-03")
    run(db, "anadir", "3", "comida", "--fecha", "2026-10-04")
    csv_path = tmp_path / "gastos.csv"
    csv_path.write_text(run(db, "exportar")[1], encoding="utf-8")

    otra = str(tmp_path / "otra.db")
    code, out = run(otra, "importar", str(csv_path))
    assert code == 0 and "2 gastos importados" in out
    gastos = Almacen(otra).listar()
    assert [(g.fecha, g.importe, g.categoria, g.descripcion) for g in gastos] == [
        (date(2026, 10, 3), 999, "libros", "novela, tapa dura"),
        (date(2026, 10, 4), 300, "comida", ""),
    ]


def test_importar_con_error_no_importa_nada(db, tmp_path, capsys):
    csv_path = tmp_path / "malo.csv"
    csv_path.write_text(
        "fecha,importe,categoria,descripcion\n2026-10-01,5,ocio,ok\n2026-13-01,5,ocio,mal\n",
        encoding="utf-8",
    )
    assert run(db, "importar", str(csv_path))[0] == 1
    assert "Línea 3" in capsys.readouterr().err
    assert Almacen(db).listar() == []


def test_importar_fichero_inexistente(db, tmp_path):
    assert run(db, "importar", str(tmp_path / "no-existe.csv"))[0] == 1


# --- comparación con el mes anterior ---------------------------------------
def test_mes_anterior():
    from gastos.cli import mes_anterior

    assert mes_anterior("2026-01") == "2025-12"
    assert mes_anterior("2026-10") == "2026-09"


def test_resumen_compara_con_mes_anterior(db):
    run(db, "anadir", "100", "comida", "--fecha", "2026-09-10")
    run(db, "anadir", "125", "comida", "--fecha", "2026-10-10")
    run(db, "anadir", "40", "ocio", "--fecha", "2026-09-10")
    run(db, "anadir", "30", "ocio", "--fecha", "2026-10-10")
    run(db, "anadir", "8", "libros", "--fecha", "2026-10-10")
    _, out = run(db, "resumen", "--mes", "2026-10")
    lineas = {linea.split()[0]: linea for linea in out.splitlines()[1:]}
    assert "+25,00 € (+25%)" in lineas["comida"]
    assert "-10,00 € (-25%)" in lineas["ocio"]
    assert "nuevo" in lineas["libros"]
    assert "+23,00 € (+16%)" in lineas["TOTAL"]
