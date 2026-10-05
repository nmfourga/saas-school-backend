-- =============================================================================
-- SCHÉMA D'INITIALISATION SQL - MODULE 1 : ADMISSIONS, INSCRIPTIONS & PAIEMENTS
-- Plateforme SaaS de Gestion Scolaire Informatisée
-- Dialecte : PostgreSQL 14+ / ANSI SQL
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -----------------------------------------------------------------------------
-- 1. SÉCURITÉ & ACCÈS (RBAC)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    telephone VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    type_utilisateur VARCHAR(30) NOT NULL CHECK (type_utilisateur IN ('PARENT', 'STAFF', 'SYSTEM')),
    est_actif BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS roles (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    libelle VARCHAR(100) NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS permissions (
    id SERIAL PRIMARY KEY,
    code VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

-- -----------------------------------------------------------------------------
-- 2. CONFIGURATION DE L'ÉTABLISSEMENT & CAMPAGNES
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS campagnes_admission (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code_annee VARCHAR(20) NOT NULL UNIQUE, -- ex: '2026-2027'
    libelle VARCHAR(100) NOT NULL,
    date_debut DATE NOT NULL,
    date_fin DATE NOT NULL,
    delai_reservation_defaut_jours INT NOT NULL DEFAULT 7,
    est_active BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS niveaux_etudes (
    id SERIAL PRIMARY KEY,
    code VARCHAR(20) UNIQUE NOT NULL, -- ex: 'NIV_6EME'
    libelle VARCHAR(100) NOT NULL,
    capacite_max INT NOT NULL DEFAULT 30,
    delai_reservation_specifique_jours INT DEFAULT NULL,
    ordre INT NOT NULL DEFAULT 0
);

-- -----------------------------------------------------------------------------
-- 3. CANDIDATS, TUTEURS & PROSPECTS
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS tuteurs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE SET NULL,
    nom VARCHAR(100) NOT NULL,
    prenom VARCHAR(100) NOT NULL,
    profession VARCHAR(100),
    adresse_postale TEXT NOT NULL,
    ville VARCHAR(100) NOT NULL,
    pays VARCHAR(100) NOT NULL DEFAULT 'Sénégal',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS candidats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reference_dossier VARCHAR(50) UNIQUE NOT NULL, -- ex: 'CAND-2026-0001'
    nom VARCHAR(100) NOT NULL,
    prenom VARCHAR(100) NOT NULL,
    date_naissance DATE NOT NULL,
    genre CHAR(1) NOT NULL CHECK (genre IN ('M', 'F')),
    niveau_id INT NOT NULL REFERENCES niveaux_etudes(id),
    campagne_id UUID NOT NULL REFERENCES campagnes_admission(id),
    statut_pipeline VARCHAR(30) NOT NULL DEFAULT 'PROSPECT' CHECK (
        statut_pipeline IN (
            'PROSPECT', 'DOSSIER_SOUMIS', 'EN_VERIFICATION', 
            'EN_EVALUATION', 'ADMIS', 'INSCRIT', 
            'DOSSIER_INCOMPLET', 'LISTE_ATTENTE', 'REFUSE', 'ABANDON'
        )
    ),
    date_offre_emise TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    date_echeance_reservation TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    motif_derogation_delai TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS candidat_tuteurs (
    candidat_id UUID NOT NULL REFERENCES candidats(id) ON DELETE CASCADE,
    tuteur_id UUID NOT NULL REFERENCES tuteurs(id) ON DELETE CASCADE,
    lien_parente VARCHAR(30) NOT NULL CHECK (lien_parente IN ('PERE', 'MERE', 'TUTEUR_LEGAL')),
    est_responsable_legal BOOLEAN NOT NULL DEFAULT TRUE,
    est_payeur_principal BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (candidat_id, tuteur_id)
);

-- -----------------------------------------------------------------------------
-- 4. COFFRE-FORT NUMÉRIQUE & ÉVALUATIONS
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS documents_candidat (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    candidat_id UUID NOT NULL REFERENCES candidats(id) ON DELETE CASCADE,
    type_document VARCHAR(50) NOT NULL CHECK (
        type_document IN ('ACTE_NAISSANCE', 'CARNET_VACCINS', 'JUSTIFICATIF_DOMICILE', 'BULLETINS', 'EXEAT')
    ),
    fichier_url VARCHAR(500) NOT NULL,
    statut_validation VARCHAR(20) NOT NULL DEFAULT 'EN_ATTENTE' CHECK (
        statut_validation IN ('EN_ATTENTE', 'VALIDE', 'REJETE')
    ),
    motif_rejet TEXT DEFAULT NULL,
    verifie_par_user_id UUID REFERENCES users(id),
    verifie_le TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS evaluations_candidat (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    candidat_id UUID NOT NULL REFERENCES candidats(id) ON DELETE CASCADE,
    date_rdv TIMESTAMP WITH TIME ZONE NOT NULL,
    evaluateur_user_id UUID NOT NULL REFERENCES users(id),
    note_test DECIMAL(5, 2) DEFAULT NULL,
    avis_commission VARCHAR(20) DEFAULT NULL CHECK (avis_commission IN ('FAVORABLE', 'RESERVE', 'DEFAVORABLE')),
    commentaires TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- 5. FACTURATION, MOBILE MONEY & AUTO-SWEEP
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS echeanciers_paiement (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    candidat_id UUID NOT NULL REFERENCES candidats(id) ON DELETE CASCADE,
    mode_frequence VARCHAR(20) NOT NULL CHECK (mode_frequence IN ('ANNUEL', 'TRIMESTRIEL', 'MENSUEL')),
    montant_total_scolarite DECIMAL(12, 2) NOT NULL,
    montant_acompte_reservation DECIMAL(12, 2) NOT NULL,
    est_acompte_regle BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transactions_paiement (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reference_transaction VARCHAR(100) UNIQUE NOT NULL,
    candidat_id UUID NOT NULL REFERENCES candidats(id),
    echeancier_id UUID REFERENCES echeanciers_paiement(id),
    type_paiement VARCHAR(30) NOT NULL CHECK (
        type_paiement IN ('FRAIS_DOSSIER', 'ACOMPTE_RESERVATION', 'ECHEANCE_SCOLARITE')
    ),
    moyen_paiement VARCHAR(50) NOT NULL CHECK (
        moyen_paiement IN (
            'MOBILE_MONEY_ORANGE', 'MOBILE_MONEY_MTN', 'MOBILE_MONEY_WAVE', 
            'MOBILE_MONEY_MOOV', 'CARTE_BANCAIRE', 'ESPECES', 'VIREMENT'
        )
    ),
    montant_brut DECIMAL(12, 2) NOT NULL,
    frais_prestataire DECIMAL(12, 2) DEFAULT 0.00,
    montant_net DECIMAL(12, 2) NOT NULL,
    devise VARCHAR(3) NOT NULL DEFAULT 'XOF',
    statut_transaction VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (
        statut_transaction IN ('PENDING', 'SUCCESS', 'FAILED', 'CANCELLED')
    ),
    gateway_psp_name VARCHAR(50) NOT NULL, -- CinetPay, PayDunya, Bizao, etc.
    gateway_transaction_id VARCHAR(150),
    telephone_payeur VARCHAR(50),
    
    -- AUTO-SWEEP / REVERSEMENT BANCAIRE AUTOMATIQUE
    statut_reversement_bancaire VARCHAR(30) NOT NULL DEFAULT 'EN_ATTENTE_SWEEP' CHECK (
        statut_reversement_bancaire IN ('EN_ATTENTE_SWEEP', 'REVERSE_BANQUE', 'ECHEC_SWEEP')
    ),
    reference_virement_bancaire VARCHAR(100) DEFAULT NULL,
    date_reversement_bancaire TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    
    date_paiement TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- 6. REGISTRE MATRICULE SIS & AUDIT TRAIL
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS eleves_sis (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    matricule_unique VARCHAR(50) UNIQUE NOT NULL, -- ex: 'MAT-2026-0042'
    candidat_id UUID UNIQUE NOT NULL REFERENCES candidats(id),
    date_conversion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    statut_eleve VARCHAR(20) NOT NULL DEFAULT 'ACTIF' CHECK (
        statut_eleve IN ('ACTIF', 'SUSPENDU', 'RADIE')
    )
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    entite_nom VARCHAR(50) NOT NULL,
    entite_id UUID NOT NULL,
    action VARCHAR(50) NOT NULL,
    effectue_par_user_id UUID REFERENCES users(id),
    details_json JSONB DEFAULT NULL,
    ip_address VARCHAR(45),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- INDEX DE PERFORMANCE
-- -----------------------------------------------------------------------------

CREATE INDEX idx_candidats_statut ON candidats(statut_pipeline);
CREATE INDEX idx_candidats_campagne_niveau ON candidats(campagne_id, niveau_id);
CREATE INDEX idx_candidats_echeance ON candidats(date_echeance_reservation) WHERE statut_pipeline = 'ADMIS';
CREATE INDEX idx_documents_candidat_statut ON documents_candidat(candidat_id, statut_validation);
CREATE INDEX idx_transactions_candidat ON transactions_paiement(candidat_id);
CREATE INDEX idx_transactions_statut_sweep ON transactions_paiement(statut_reversement_bancaire, statut_transaction);
CREATE INDEX idx_audit_entite ON audit_logs(entite_nom, entite_id);

-- -----------------------------------------------------------------------------
-- DONNÉES INITIALES (SEED DATA)
-- -----------------------------------------------------------------------------

-- Permissions
INSERT INTO permissions (code, description) VALUES
('prospects.create_read', 'Consulter et créer des prospects/candidats'),
('documents.validate', 'Valider ou rejeter les pièces du coffre-fort numérique'),
('assessment.rate_interview', 'Saisir les notes et avis de la commission d''admission'),
('admission.approve_offer', 'Prononcer l''admission et émettre le contrat'),
('fees.configure_discount', 'Accorder des remises financières exceptionnelles'),
('sis.trigger_conversion', 'Exécuter la conversion du candidat admis vers le registre SIS')
ON CONFLICT (code) DO NOTHING;

-- Rôles
INSERT INTO roles (code, libelle, description) VALUES
('ROLE_SUPER_ADMIN', 'Administrateur Général', 'Accès complet au système'),
('ROLE_ADMISSIONS_ADMIN', 'Responsable Admissions', 'Gestion globale du pipeline de recrutement'),
('ROLE_DOC_REVIEWER', 'Vérificateur Documentaire', 'Habilité à contrôler et valider les pièces justificatives'),
('ROLE_PEDAGOGIC_HEAD', 'Directeur Pédagogique', 'Évaluation des candidats et avis commission'),
('ROLE_FINANCE', 'Gestionnaire Financier', 'Suivi des encaissements Mobile Money et reversements bancaires'),
('ROLE_PARENT', 'Espace Famille', 'Soumission de dossier, pièces et paiements')
ON CONFLICT (code) DO NOTHING;

-- Association Rôles - Permissions
-- ROLE_DOC_REVIEWER
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p 
WHERE r.code = 'ROLE_DOC_REVIEWER' AND p.code IN ('prospects.create_read', 'documents.validate')
ON CONFLICT DO NOTHING;

-- ROLE_ADMISSIONS_ADMIN
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p 
WHERE r.code = 'ROLE_ADMISSIONS_ADMIN'
ON CONFLICT DO NOTHING;

-- Campagne par défaut
INSERT INTO campagnes_admission (code_annee, libelle, date_debut, date_fin, delai_reservation_defaut_jours, est_active)
VALUES ('2026-2027', 'Campagne d''Admission 2026-2027', '2026-01-15', '2026-09-30', 7, TRUE)
ON CONFLICT DO NOTHING;

-- Niveaux d'études
INSERT INTO niveaux_etudes (code, libelle, capacite_max, ordre) VALUES
('NIV_CP', 'Classe de CP', 25, 1),
('NIV_CE1', 'Classe de CE1', 25, 2),
('NIV_CE2', 'Classe de CE2', 25, 3),
('NIV_CM1', 'Classe de CM1', 30, 4),
('NIV_CM2', 'Classe de CM2', 30, 5),
('NIV_6EME', 'Classe de 6ème', 30, 6),
('NIV_5EME', 'Classe de 5ème', 30, 7),
('NIV_4EME', 'Classe de 4ème', 30, 8),
('NIV_3EME', 'Classe de 3ème', 30, 9),
('NIV_2NDE', 'Classe de 2nde', 35, 10),
('NIV_1ERE', 'Classe de 1ère', 35, 11),
('NIV_TLE', 'Classe de Terminale', 35, 12)
ON CONFLICT DO NOTHING;
