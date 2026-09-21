# Skafferiet — R8 / ProGuard regler for release-builds.
#
# Flutter-pluginet tilfoejer selv de noedvendige regler for Flutter-engine og
# -embedding, og Firebase-bibliotekerne leverer deres egne consumer-regler.
# Herunder staar kun det, som projektet selv har brug for.

# Bevar stacktraces laesbare i Play Console. Uden disse bliver linjenumre
# fjernet, og crash-rapporter bliver reelt ubrugelige.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Annotationer og generics bruges af Firestore/Gson-lignende serialisering.
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses,EnclosingMethod

# Flutter refererer Play Core (deferred components / split install), men
# biblioteket er ikke med i denne app. Uden dette fejler R8 paa manglende klasser.
-dontwarn com.google.android.play.core.**

# Firebase/gRPC trækker valgfrie compile-time annotationer ind, som ikke
# findes paa runtime.
-dontwarn javax.annotation.**
-dontwarn javax.naming.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
