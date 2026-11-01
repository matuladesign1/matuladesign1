# Sermons de Branham Matomate

Application biblique Android — **Matula Design & Pasteur Ben MATOMATE**
© (année en cours, calculée automatiquement) Matula Design & Pasteur Ben MATOMATE. Tous droits réservés.

Bible complète (Louis Segond 1910, 66 livres, 31 102 versets), bibliothèque de prédications
importées, recherche intégrale (Mots / Exacte / Sens), assistant IA avec citations vérifiables,
traduction lingala, notes, favoris, surlignages, plans de lecture, mode hors ligne.

---

## 1. Obtenir l'APK (sans rien installer sur votre ordinateur)

Le projet contient une chaîne de compilation automatique (GitHub Actions) qui compile **et teste**
l'application à chaque modification.

1. Créez un compte gratuit sur https://github.com et un dépôt privé (ex. `sermons-branham-matomate`).
2. Dans le dépôt : **Add file → Upload files**, déposez **tout le contenu** de ce dossier
   (y compris le dossier caché `.github`), puis **Commit changes**.
3. Ouvrez l'onglet **Actions** : la compilation démarre (≈ 10 à 15 minutes).
4. Quand la coche est verte, cliquez sur l'exécution, puis sur l'artefact
   **SermonsBranhamMatomate-android** en bas de page. Il contient :
   - `SermonsBranhamMatomate-test.apk` — APK de test (debug) ;
   - `SermonsBranhamMatomate.apk` — APK Release, installable directement ;
   - `SermonsBranhamMatomate.aab` — fichier pour Google Play.
5. Sur le téléphone : ouvrez l'APK, autorisez « Installer des applications inconnues », installez.

Une deuxième tâche teste l'application sur des émulateurs **Android 7.0** et **Android 13**
(démarrage, Bible, recherche, plans).

### Signature pour Google Play
Sans clé, l'APK Release est signé avec une clé de test (installable, mais pas publiable sur le Play Store).
Pour publier : créez une clé (`keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`),
puis ajoutez dans **Settings → Secrets → Actions** du dépôt :
`KEYSTORE_BASE64` (contenu du .jks en base64), `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
Gardez cette clé en lieu sûr : elle est indispensable pour chaque mise à jour.

## 2. Compiler sur un ordinateur (facultatif)

Prérequis : Flutter 3.27.4, Android Studio (SDK Android), Java 17.

```bash
flutter create --platforms=android --org com.matuladesign --project-name sermons_branham_matomate .
python3 tools/patch_android.py
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter test
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release  # pour Google Play
```

## 3. Ajouter les prédications

L'application ne contient **aucun sermon inventé** : la bibliothèque se remplit uniquement par import.

**Sur le téléphone** — Paramètres → Importer des prédications : PDF (un ou plusieurs), ZIP, packs `.smpack`,
ou dossier complet. Titre, code (ex. `47-0412`), date, année, lieu, langue et paragraphes sont reconnus
automatiquement ; les doublons sont écartés ; les documents douteux sont marqués « à vérifier ».

**Sur ordinateur (recommandé pour des centaines/milliers de fichiers, et pour les PDF scannés avec OCR)** :

```bash
# prérequis : poppler-utils, tesseract-ocr, tesseract-ocr-fra
python3 tools/import_sermons.py bibliotheque.smpack /chemin/vers/pdfs/ archives.zip \
    --source "Provenance et autorisation (ex. lettre du ...)" \
    --series series.csv --audio audio.csv
```

- `series.csv` : colonnes `code,series` (ex. `63-0318,La Révélation des Sept Sceaux`)
- `audio.csv` : colonnes `code,audio_url,duration_sec` (uniquement des liens autorisés)
- Un rapport `bibliotheque-rapport.csv` liste chaque fichier : ok, doublon, à vérifier, échec.

Copiez ensuite `bibliotheque.smpack` sur le téléphone et importez-le.

## 4. Assistant IA, recherche par le sens, traduction lingala (serveur)

Sans serveur, tout fonctionne hors ligne ; l'assistant affiche les passages exacts trouvés (sans synthèse)
et le mode « Sens » classe les passages par pertinence lexicale.

Pour activer l'IA :
1. Créez un projet sur https://supabase.com, puis appliquez `supabase/migrations/0001_schema.sql`.
2. `supabase functions deploy assistant` puis `supabase secrets set OPENAI_API_KEY=sk-...`
   (la clé OpenAI reste **uniquement sur le serveur**).
3. Publiez la bibliothèque avec les vecteurs :
   `python3 tools/upload_pack_to_supabase.py bibliotheque.smpack --publish`
4. Dans l'application : Paramètres → Assistant IA → URL et clé « anon » du projet.

## 5. Bible

`assets/db/bible.db` est généré par `tools/build_bible_db.py` à partir de la Louis Segond 1910
(domaine public). Une autre version (dont une Bible lingala autorisée) s'ajoute avec le même outil :
`python3 tools/build_bible_db.py fichier.xml assets/db/bible.db CODE "Nom" ln`
puis incrémentez `bibleAssetVersion` dans `lib/data/db.dart`.

## 6. Structure

```
lib/core      thème (bleu profond / or, sombre & clair), textes FR/LN, préférences
lib/data      base SQLite + FTS5, recherche, import, notes/favoris, plans, audio, IA
lib/ui        écrans : Accueil, Demander, Chercher (+ Index), Bible, Plans, lecteur, notes, profil, paramètres
tools/        import PDF/OCR, construction de la Bible, publication serveur, préparation Android
supabase/     schéma serveur (rôles, RLS, pgvector) et fonction « assistant »
test/, integration_test/   tests unitaires et tests sur émulateur
docs/ANALYSE.md   analyse, sources, droits, architecture, état d'avancement par phase
```
