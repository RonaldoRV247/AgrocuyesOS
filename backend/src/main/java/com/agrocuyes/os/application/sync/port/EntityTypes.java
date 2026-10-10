package com.agrocuyes.os.application.sync.port;

/**
 * Identificadores de entidad del protocolo de sync. Son STRINGS, no enums de
 * dominio: el catalogo es dinamico y una entidad nueva definida por el usuario
 * o por una ingesta IA debe poder incorporarse sin partir el contrato del API.
 */
public final class EntityTypes {

    public static final String TERRENO = "terreno";
    public static final String PLANTILLA_PROCESO = "plantilla_proceso";
    public static final String REGISTRO_ACTIVIDAD = "registro_actividad";
    public static final String GALPON = "galpon";
    public static final String POZA = "poza";
    public static final String EVENTO_POZA = "evento_poza";

    private EntityTypes() {
    }
}
