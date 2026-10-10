package com.agrocuyes.os.domain.cria;

import com.agrocuyes.os.domain.shared.SyncableEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.UUID;

/**
 * Galpon: instalacion fisica que agrupa pozas.
 */
@Entity
@Table(name = "galpon")
@Getter
@Setter
@NoArgsConstructor
public class Galpon extends SyncableEntity {

    @Column(name = "nombre", nullable = false, length = 150)
    private String nombre;

    @Column(name = "capacidad_maxima")
    private Integer capacidadMaxima;

    @Column(name = "owner_id", nullable = false)
    private UUID ownerId;

    public static Galpon crear(long now, UUID id, String nombre, UUID ownerId, Integer capacidadMaxima) {
        var galpon = new Galpon();
        galpon.initIdentity(id, now);
        galpon.nombre = nombre;
        galpon.ownerId = ownerId;
        galpon.capacidadMaxima = capacidadMaxima;
        return galpon;
    }

    public void aplicarDesde(long incomingUpdatedAt, String nombre, Integer capacidadMaxima) {
        this.nombre = nombre;
        this.capacidadMaxima = capacidadMaxima;
        touch(incomingUpdatedAt);
    }
}
