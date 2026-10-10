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
 * Poza: corral dentro de un galpon donde convive un lote de cuyes.
 * Es el sujecto de las transacciones del core de crianza (ver EventoPoza).
 */
@Entity
@Table(name = "poza")
@Getter
@Setter
@NoArgsConstructor
public class Poza extends SyncableEntity {

    @Column(name = "galpon_id", columnDefinition = "uuid", nullable = false)
    private UUID galponId;

    @Column(name = "codigo", nullable = false, length = 40)
    private String codigo;

    @Column(name = "hembras")
    private Integer hembras;

    @Column(name = "machos")
    private Integer machos;

    @Column(name = "crias")
    private Integer crias;

    public static Poza crear(long now, UUID id, UUID galponId, String codigo) {
        var poza = new Poza();
        poza.initIdentity(id, now);
        poza.galponId = galponId;
        poza.codigo = codigo;
        return poza;
    }

    public void aplicarDesde(long incomingUpdatedAt, UUID galponId, String codigo,
                             Integer hembras, Integer machos, Integer crias) {
        this.galponId = galponId;
        this.codigo = codigo;
        this.hembras = hembras;
        this.machos = machos;
        this.crias = crias;
        touch(incomingUpdatedAt);
    }
}
