#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
catalog="$project_root/Resources/Localizable.xcstrings"
translations="$project_root/scripts/localization-en.json"
protocol_translations="$project_root/scripts/localization-pc27-en.json"
score_detail_translations="$project_root/scripts/localization-pc28-en.json"
first_curation_translations="$project_root/scripts/localization-pc29-en.json"
similarity_translations="$project_root/scripts/localization-pc30-en.json"
photo_progress_translations="$project_root/scripts/localization-pc31-en.json"
global_score_translations="$project_root/scripts/localization-pc33-en.json"
brand_model_translations="$project_root/scripts/localization-pc34-en.json"
guide_spotlight_translations="$project_root/scripts/localization-pc35-en.json"
people_scenery_translations="$project_root/scripts/localization-pc36-en.json"
temporary_file="$(mktemp "$project_root/Resources/.Localizable.xcstrings.XXXXXX")"
trap 'rm -f "$temporary_file"' EXIT

missing="$(
  jq \
    --slurpfile translations "$translations" \
    --slurpfile protocol_translations "$protocol_translations" \
    --slurpfile score_detail_translations "$score_detail_translations" \
    --slurpfile first_curation_translations "$first_curation_translations" \
    --slurpfile similarity_translations "$similarity_translations" \
    --slurpfile photo_progress_translations "$photo_progress_translations" \
    --slurpfile global_score_translations "$global_score_translations" \
    --slurpfile brand_model_translations "$brand_model_translations" \
    --slurpfile guide_spotlight_translations "$guide_spotlight_translations" \
    --slurpfile people_scenery_translations "$people_scenery_translations" '
    (
      $translations[0]
      * $protocol_translations[0]
      * $score_detail_translations[0]
      * $first_curation_translations[0]
      * $similarity_translations[0]
      * $photo_progress_translations[0]
      * $global_score_translations[0]
      * $brand_model_translations[0]
      * $guide_spotlight_translations[0]
      * $people_scenery_translations[0]
    ) as $all_translations
    |
    [
      .strings
      | to_entries[]
      | select(.value.extractionState != "stale")
      | .key
      | select(test("[一-龥]"))
      | select($all_translations[.] == null)
    ]
  ' "$catalog"
)"

if [[ "$missing" != "[]" ]]; then
  printf 'Missing English translations:\n%s\n' "$missing" >&2
  exit 1
fi

jq \
  --indent 2 \
  --slurpfile translations "$translations" \
  --slurpfile protocol_translations "$protocol_translations" \
  --slurpfile score_detail_translations "$score_detail_translations" \
  --slurpfile first_curation_translations "$first_curation_translations" \
  --slurpfile similarity_translations "$similarity_translations" \
  --slurpfile photo_progress_translations "$photo_progress_translations" \
  --slurpfile global_score_translations "$global_score_translations" \
  --slurpfile brand_model_translations "$brand_model_translations" \
  --slurpfile guide_spotlight_translations "$guide_spotlight_translations" \
  --slurpfile people_scenery_translations "$people_scenery_translations" '
  (
    $translations[0]
    * $protocol_translations[0]
    * $score_detail_translations[0]
    * $first_curation_translations[0]
    * $similarity_translations[0]
    * $photo_progress_translations[0]
    * $global_score_translations[0]
    * $brand_model_translations[0]
    * $guide_spotlight_translations[0]
    * $people_scenery_translations[0]
  ) as $all_translations
  |
  .strings |= with_entries(
    select(.value.extractionState != "stale")
    | .value.localizations.en.stringUnit = {
        "state": "translated",
        "value": ($all_translations[.key] // .key)
      }
  )
' "$catalog" > "$temporary_file"

mv "$temporary_file" "$catalog"
trap - EXIT
printf 'Applied English translations to %s\n' "$catalog"
