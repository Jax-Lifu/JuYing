package com.flytech.juying.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SidecarCoversTest {
    @Test fun directoryIndexPreservesMatchingOrderSuffixesAndVideoFallbacks() {
        val files = listOf(
            video("Movie.mp4"), video("Clip.mkv"), video("Film.mp4"), video("Movie-thumb2.mp4"),
            video("Orphan.mp4"), video("Missing.mp4"),
            FileEntry("folder.jpg", "folder.jpg", false, uri = "folder-cover"),
            FileEntry("Movie.jpg", "directory", true, uri = "directory-cover"),
            image("MOVIE-thumb2-thumb3.jpg"), image("Movie.jpg"), image("Clip.thumb-small.png"),
            image("Film-poster-hi.jpg"), image("Missing.jpg").copy(uri = null), image("Missing-thumb.jpg"),
            FileEntry("notes.txt", "notes.txt", false),
        )

        assertEquals(mapOf(
            "Movie.mp4" to "cover:MOVIE-thumb2-thumb3.jpg",
            "Clip.mkv" to "cover:Clip.thumb-small.png",
            "Film.mp4" to "cover:Film-poster-hi.jpg",
            "Movie-thumb2.mp4" to "cover:MOVIE-thumb2-thumb3.jpg",
            "Orphan.mp4" to "video:Orphan.mp4",
            "Missing.mp4" to "video:Missing.mp4",
        ), SidecarCovers.forDirectory(files))
    }

    @Test fun largeDirectoryWithoutPicturesIsVisitedLinearly() {
        val videos = List(5_000) { video("episode-$it.mp4") }
        var visits = 0
        val counted = object : AbstractList<FileEntry>() {
            override val size get() = videos.size
            override fun get(index: Int): FileEntry { visits++; return videos[index] }
        }

        val covers = SidecarCovers.forDirectory(counted)

        assertEquals(videos.size, covers.size)
        assertTrue("Directory matching visited $visits entries", visits <= videos.size * 3)
        videos.forEach { assertEquals(it.uri, covers[it.path]) }
    }

    private fun video(name: String) = FileEntry(name, name, false, uri = "video:$name")
    private fun image(name: String) = FileEntry(name, name, false, uri = "cover:$name")
}
