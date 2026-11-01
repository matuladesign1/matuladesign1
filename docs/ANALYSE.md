# Analyse, architecture et état d'avancement

## 1. Sources des prédications et droits

| Source | Contenu | Remarque |
|---|---|---|
| branham.org (Voice of God Recordings) | audios, textes, traductions françaises | Collection officielle. Les enregistrements, transcriptions et traductions sont protégés : une **autorisation écrite** est nécessaire pour les redistribuer dans une application. |
| branham.fr | textes français | Vérifier les conditions d'utilisation du site et l'origine des traductions. |
| Living Word Broadcast (lwbcast.org) | index de textes et lecteur audio | Idem : demander l'autorisation avant toute redistribution. |

Conséquence technique : l'application **n'embarque aucun sermon**. Elle fournit un système d'import
massif (PDF, dossiers, ZIP, packs) qui conserve la source et le fichier d'origine de chaque document.
Le nombre visé (≥ 1 244) dépend des archives authentiques que vous importerez ; l'outil signale les
doublons et les références manquantes au lieu d'inventer quoi que ce soit.

Modèle de demande d'autorisation : préciser l'application (gratuite, sans publicité), les contenus
(textes français, audios), le public (églises de RDC et francophones), et l'engagement de citer la source.

## 2. Bible

- **Français** : Louis Segond 1910 — domaine public — intégrée (66 livres, 1 189 chapitres, 31 102 versets).
- **Lingala** : les versions courantes (*Mokanda na Bomoi*, Biblica 2002/2020 ; *Biblia* de l'Alliance
  biblique) sont protégées. Elles ne sont pas intégrées. Démarche : demander une licence à Biblica
  ou à la Société biblique du Congo, puis ajouter la version avec `tools/build_bible_db.py`.
  Aucune traduction automatique n'est présentée comme Bible officielle.

## 3. Architecture

- **Flutter 3.27 / Dart**, Material 3 personnalisé (bleu #071D45 / #123E78, or #E6B63E), thèmes sombre et clair.
- **SQLite + FTS5** (bibliothèque `sqlite3_flutter_libs`) : index plein texte insensible aux accents
  (`unicode61 remove_diacritics 2`) sur les paragraphes des sermons, les versets et les notes.
  - *Mots* : tous les mots requis, dans n'importe quel ordre.
  - *Exacte* : expression exacte, dans l'ordre.
  - *Sens* : hors ligne, mots significatifs + termes apparentés classés par pertinence (BM25) ;
    en ligne, recherche vectorielle (pgvector, `text-embedding-3-small`).
  - Correction des fautes simples (distance d'édition sur le vocabulaire indexé), suggestions,
    historique, pagination progressive, contexte avant/après.
- **Import** dans un isolat séparé (l'interface reste fluide) ; OCR via l'outil ordinateur (Tesseract).
- **Assistant IA (RAG)** : recherche réelle d'abord, puis synthèse côté serveur avec consigne stricte
  (citer chaque affirmation, ne jamais inventer de citation). Les passages affichés sont toujours relus
  dans la base locale. Clé OpenAI uniquement côté serveur.
- **Serveur Supabase** : PostgreSQL, recherche plein texte, pgvector, rôles (super administrateur,
  administrateur, traducteur, éditeur, utilisateur) avec sécurité au niveau des lignes.

## 4. État d'avancement (version 1.0)

| Phase | Statut |
|---|---|
| 1. Analyse et architecture | ✅ ce document |
| 2. Design UI/UX (captures reproduites) | ✅ thème, icônes Material homogènes, paysages vectoriels hors ligne |
| 3. Navigation et écrans | ✅ Accueil, Demander, Chercher (+ Index), Bible, Plans, Bibliothèque, Notes, Profil, Paramètres |
| 4. Base de données et import PDF | ✅ PDF, multi-fichiers, dossiers, ZIP, packs ; métadonnées, langue, doublons ; OCR sur ordinateur |
| 5. Bibliothèque et lecteur | ✅ classements année/A-Z/séries/lieu/durée, lecteur numéroté, surlignage, notes, partage, PDF, audio (arrière-plan, notification, ±15 s, vitesses) |
| 6. Bible complète | ✅ LSG 1910, navigation, recherche, surlignage, notes, favoris, lecture vocale, historique |
| 7. Moteur de recherche | ✅ Mots / Exacte / Sens, toute la bibliothèque + Bible + notes |
| 8. IA et traduction lingala | ✅ client + fonction serveur ; à activer avec votre projet Supabase et votre clé OpenAI |
| 9. Notes, favoris, plans, profil, badges | ✅ local ; synchronisation multi-appareils : schéma serveur prêt, connexion des comptes à faire (v1.1) |
| 10. Tests et APK | ✅ tests unitaires + tests sur émulateurs Android 7.0 et 13 + compilation APK/AAB automatisée |

Reste à faire (v1.1) : notifications planifiées (verset du jour, rappels), connexion des comptes
et synchronisation, tableau de bord administrateur web (le schéma des rôles est prêt),
synchronisation texte/audio (nécessite des repères temporels par paragraphe), relecture des
libellés lingala de l'interface par un locuteur natif.
