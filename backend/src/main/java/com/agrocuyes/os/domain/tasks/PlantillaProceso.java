package com.agrocuyes.os.domain.tasks;

import com.agrocuyes.os.domain.shared.SyncableEntity;
import io.hypersistence.utils.hibernate.type.json.JsonBinaryType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.Type;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Catalogo dinamico de actividades (Riego, Siembra, Fertilizacion...).
 * No existe ningun enum de "tipo de actividad": el usuario (o un agente IA)
 * crea tipos nuevos en tiempo de ejecucion.
 */
@Entity
@Table(name = "plantilla_proceso")
@Getter
@Setter
@NoArgsConstructor
public class PlantillaProceso extends SyncableEntity {

    @Column(name = "nombre", nullable = false, length = 120)
    private String nombre;

    /** Pasos, herramientas, insumos... atributos variables sin tocar el esquema. */
    @Type(JsonBinaryType.class)
    @Column(name = "metadata", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> metadata = new LinkedHashMap<>();

    @Column(name = "activo", nullable = false)
    private boolean activo = true;

    public static PlantillaProceso crear(long now, UUID id, String nombre, Map<String, Object> metadata) {
        var plantilla = new PlantillaProceso();
        plantilla.initIdentity(id, now);
        plantilla.nombre = nombre;
        plantilla.metadata = metadata == null ? new LinkedHashMap<>() : new LinkedHashMap<>(metadata);
        return plantilla;
    }

    public void aplicarDesde(long incomingUpdatedAt, String nombre, Map<String, Object> metadata, boolean activo) {
        this.nombre = nombre;
        this.metadata = metadata == null ? new LinkedHashMap<>() : new LinkedHashMap<>(metadata);
        this.activo = activo;
        touch(incomingUpdatedAt);
    }
}
