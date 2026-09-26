# R8 rules for release builds. Verified against a release build (see README).

# google_mlkit_text_recognition references the optional script-specific
# recognizers (Chinese, Devanagari, Japanese, Korean). Only the bundled Latin
# recognizer is used, so the missing classes are expected.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
