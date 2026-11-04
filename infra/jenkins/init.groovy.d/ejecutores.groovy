// Un solo build a la vez: dos compilaciones de Android en paralelo (Gradle con -Xmx2048m cada una,
// más el daemon de Kotlin) agotan la memoria de Docker Desktop (~5 GB) y el sistema mata a Gradle
// ("Gradle build daemon disappeared unexpectedly"). Los demás builds esperan en la cola.
import jenkins.model.Jenkins

Jenkins.get().setNumExecutors(1)
