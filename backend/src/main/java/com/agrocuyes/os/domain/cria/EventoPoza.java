package com.agrocuyes.os.domain.cria;

import com.agrocuyes.os.domain.shared.SyncableEntity;
import io.hypersistence.utils.hibernate.type.json.JsonBinaryType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.Type;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Transaccion del core de crianza: un hecho sobre una poza (Monta, Parto,
 * Destete, Mortalidad,weight...).
 *
 * IMPORTANTE: `tipo_evento` es un TEXT libre que referencia al catalogo dinamico
 * (ProcesoPersonalizado), nunca un enum de Java. Agregar "Vaccination" o un
 * tipo inventado por un modelo IA no debe requerir deploy.
 */
@Entity
@Table(name = "evento_poza")
@Getter
@Setter
@NoArgsConstructor
public class EventoPoza extends SyncableEntity {

    @Column(name = "poza_id", columnDefinition = "uuid", nullable = false)
    private UUID pozaId;

    /** Clave del catalogo dinamico: "monta", "parto", "destete", ... */
    @Column(name = "tipo_evento", nullable = false, length = 80)
    private String tipoEvento;

    @Column(name = "fecha_evento", nullable = false)
    private LocalDate fechaEvento;

    /**
     * JSONB: cambia la forma del dato sin cambiar el esquema.
     * Monta -> {"macho_id": "...", "peso_macho_g": 980}
     * Parto  -> {"numero_crias": 3, "peso_total_g": 240, "muerte_hembra": false}
     */
    @Type(JsonBinaryType.class)
    @Column(name = "detalles", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> detalles = new LinkedHashMap<>();

    public static EventoPoza crear(long now, UUID id, UUID pozaId, String tipoEvento,
                                   LocalDate fechaEvento, Map<String, Object> detalles) {
        var evento = new EventoPoza();
        evento.initIdentity(id, now);
        evento.pozaId = pozaId;
        evento.tipoEvento = tipoEvento;
        evento.fechaEvento = fechaEvento;
        evento.detalles = detalles == null ? new LinkedHashMap<>() : new LinkedHashMap<>(detalles);
        return evento;
    }

    public void aplicarDesde(long incomingUpdatedAt, UUID pozaId, String tipoEvento,
                             LocalDate fechaEvento, Map<String, Object> detalles) {
        this.pozaId = pozaId;
        this.tipoEvento = tipoEvento;
        this.fechaEvento = fechaEvento;
        this.detalles = detalles == null ? new LinkedHashMap<>() : new LinkedHashMap<>(detalles);
        touch(incomingUpdatedAt);
    }
}
