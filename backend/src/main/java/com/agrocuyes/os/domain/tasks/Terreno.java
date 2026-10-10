package com.agrocuyes.os.domain.tasks;

import com.agrocuyes.os.domain.shared.SyncableEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.UUID;

/**
 * Terreno / lote de cultivo. Punto de anclaje de los registros de actividad.
 */
@Entity
@Table(name = "terreno")
@Getter
@Setter
@NoArgsConstructor
public class Terreno extends SyncableEntity {

    @Column(name = "nombre", nullable = false, length = 150)
    private String nombre;

    @Column(name = "area_m2")
    private Double areaM2;

    /** Latitud/Longitud capturadas en campo (offline) con el GPS del dispositivo. */
    @Column(name = "lat")
    private Double lat;

    @Column(name = "lng")
    private Double lng;

    /** Propietario / responsable. FK logica sin @ManyToOne: el alta llega offline. */
    @Column(name = "owner_id", nullable = false)
    private UUID ownerId;

    public static Terreno crear(long now, UUID id, String nombre, UUID ownerId) {
        var terreno = new Terreno();
        terreno.initIdentity(id, now);
        terreno.nombre = nombre;
        terreno.ownerId = ownerId;
        return terreno;
    }

    public void aplicarDesde(long incomingUpdatedAt, String nombre, Double areaM2, Double lat, Double lng) {
        this.nombre = nombre;
        this.areaM2 = areaM2;
        this.lat = lat;
        this.lng = lng;
        touch(incomingUpdatedAt);
    }
}
