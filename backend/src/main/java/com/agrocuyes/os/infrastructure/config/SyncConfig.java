package com.agrocuyes.os.infrastructure.config;

import com.agrocuyes.os.application.sync.port.SyncRepository;
import com.agrocuyes.os.domain.cria.EventoPoza;
import com.agrocuyes.os.domain.cria.Galpon;
import com.agrocuyes.os.domain.cria.Poza;
import com.agrocuyes.os.domain.tasks.PlantillaProceso;
import com.agrocuyes.os.domain.tasks.RegistroActividad;
import com.agrocuyes.os.domain.tasks.Terreno;
import com.agrocuyes.os.infrastructure.persistence.JpaSyncRepository;
import jakarta.persistence.EntityManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.function.LongSupplier;

/**
 * Cableado de la capa de aplicacion hacia afuera.
 */
@Configuration
public class SyncConfig {

    /**
     * Reloj unico del sistema de sync. Epoch-millis UTC, inyectable: los tests
     * del arbitraje LWW necesitan congelarlo y el server nunca debe usar
     * LocalDateTime.now() repartido por el codigo.
     */
    @Bean
    public LongSupplier syncClock() {
        return System::currentTimeMillis;
    }

    @Bean
    public SyncRepository<Terreno> terrenoSyncRepository(EntityManager em) {
        return new JpaSyncRepository<>(em, Terreno.class);
    }

    @Bean
    public SyncRepository<PlantillaProceso> plantillaProcesoSyncRepository(EntityManager em) {
        return new JpaSyncRepository<>(em, PlantillaProceso.class);
    }

    @Bean
    public SyncRepository<RegistroActividad> registroActividadSyncRepository(EntityManager em) {
        return new JpaSyncRepository<>(em, RegistroActividad.class);
    }

    @Bean
    public SyncRepository<Galpon> galponSyncRepository(EntityManager em) {
        return new JpaSyncRepository<>(em, Galpon.class);
    }

    @Bean
    public SyncRepository<Poza> pozaSyncRepository(EntityManager em) {
        return new JpaSyncRepository<>(em, Poza.class);
    }

    @Bean
    public SyncRepository<EventoPoza> eventoPozaSyncRepository(EntityManager em) {
        return new JpaSyncRepository<>(em, EventoPoza.class);
    }
}
