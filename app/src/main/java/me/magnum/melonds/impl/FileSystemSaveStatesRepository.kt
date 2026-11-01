package me.magnum.melonds.impl

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import me.magnum.melonds.common.uridelegates.UriHandler
import me.magnum.melonds.domain.model.rom.Rom
import me.magnum.melonds.domain.model.SaveStateSlot
import me.magnum.melonds.domain.repositories.SaveStatesRepository
import me.magnum.melonds.domain.repositories.SettingsRepository
import me.magnum.melonds.extensions.nameWithoutExtension
import me.magnum.melonds.ui.emulator.exceptions.SaveSlotLoadException
import java.util.*

class FileSystemSaveStatesRepository(
    private val settingsRepository: SettingsRepository,
    private val saveStateScreenshotProvider: SaveStateScreenshotProvider,
    private val uriHandler: UriHandler,
    private val context: Context
) : SaveStatesRepository {

    override fun getRomSaveStates(rom: Rom): List<SaveStateSlot> {
        val saveStateDirectoryDocument = getSaveStateDirectoryDocument(rom) ?: return emptyList()
        val romFileName = getRomFileNameWithoutExtension(rom) ?: return emptyList()

        val saveStateSlots = Array(9) {
            SaveStateSlot(it, false, null, null)
        }
        val fileNameRegex = "${Regex.escape(romFileName)}\\.ml[0-8]".toRegex()
        listSaveStateFiles(saveStateDirectoryDocument) { it.matches(fileNameRegex) }.forEach {
            val slotNumber = it.name.last().digitToInt()
            val slot = SaveStateSlot(slotNumber, true, Date(it.lastModified), null)
            val screenshotUri = saveStateScreenshotProvider.getRomSaveStateScreenshotUri(rom, slot)
            saveStateSlots[slotNumber] = slot.copy(screenshot = screenshotUri)
        }

        return saveStateSlots.toList()
    }

    override fun getRomQuickSaveStateSlot(rom: Rom): SaveStateSlot {
        val quickSaveStateDocument = getRomQuickSaveStateFile(rom)
        val saveStateExists = quickSaveStateDocument != null
        val lastModified = quickSaveStateDocument?.let { Date(it.lastModified) }
        val slot = SaveStateSlot(SaveStateSlot.QUICK_SAVE_SLOT, saveStateExists, lastModified, null)
        val screenshotUri = saveStateScreenshotProvider.getRomSaveStateScreenshotUri(rom, slot)
        return slot.copy(screenshot = screenshotUri)
    }

    override fun getRomSaveStateUri(rom: Rom, saveState: SaveStateSlot): Uri {
        val saveStateDirectoryDocument = getSaveStateDirectoryDocument(rom) ?: throw SaveSlotLoadException("Could not create parent directory document")

        val romFileName = getRomFileNameWithoutExtension(rom) ?: throw SaveSlotLoadException("Could not determine ROM file name")
        val saveStateName = "$romFileName.ml${saveState.slot}"
        val saveStateFile = listSaveStateFiles(saveStateDirectoryDocument) { it == saveStateName }.firstOrNull()

        val uri = if (saveStateFile != null) {
            saveStateFile.uri
        } else {
            saveStateDirectoryDocument.createFile("*/*", saveStateName)?.uri ?: throw SaveSlotLoadException("Could not create save state file")
        }

        return uri
    }

    override fun setRomSaveStateScreenshot(rom: Rom, saveState: SaveStateSlot, screenshot: Bitmap) {
        saveStateScreenshotProvider.saveRomSaveStateScreenshot(rom, saveState, screenshot)
    }

    override fun deleteRomSaveStateScreenshot(rom: Rom, saveState: SaveStateSlot) {
        saveStateScreenshotProvider.deleteRomSaveStateScreenshot(rom, saveState)
    }

    override fun deleteRomSaveState(rom: Rom, saveState: SaveStateSlot) {
        if (!saveState.exists) {
            return
        }

        val saveStateDirectoryDocument = getSaveStateDirectoryDocument(rom) ?: throw SaveSlotLoadException("Could not create parent directory document")
        val romFileName = getRomFileNameWithoutExtension(rom) ?: throw SaveSlotLoadException("Could not determine ROM file name")

        val saveStateName = "$romFileName.ml${saveState.slot}"
        val saveStateFile = saveStateDirectoryDocument.findFile(saveStateName)

        saveStateFile?.delete()
        saveStateScreenshotProvider.deleteRomSaveStateScreenshot(rom, saveState)
    }

    private fun getRomQuickSaveStateFile(rom: Rom): SaveStateFile? {
        val saveStateDirectoryDocument = getSaveStateDirectoryDocument(rom) ?: return null
        val romFileName = getRomFileNameWithoutExtension(rom) ?: return null

        val quickSaveStateFileName = "$romFileName.ml0"
        return listSaveStateFiles(saveStateDirectoryDocument) { it == quickSaveStateFileName }.firstOrNull()
    }

    private data class SaveStateFile(val uri: Uri, val name: String, val lastModified: Long)

    private fun listSaveStateFiles(directory: DocumentFile, matches: (String) -> Boolean): List<SaveStateFile> {
        val directoryUri = directory.uri
        if (directoryUri.scheme == "content" && DocumentsContract.isTreeUri(directoryUri)) {
            val files = try {
                val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                    directoryUri,
                    DocumentsContract.getDocumentId(directoryUri),
                )
                val projection = arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                )
                context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                    buildList<SaveStateFile> {
                        while (cursor.moveToNext()) {
                            val name = cursor.getString(1)?.takeIf(matches) ?: continue
                            val documentId = cursor.getString(0) ?: continue
                            add(SaveStateFile(
                                DocumentsContract.buildDocumentUriUsingTree(directoryUri, documentId),
                                name,
                                if (cursor.isNull(2)) 0L else cursor.getLong(2),
                            ))
                        }
                    }
                }
            } catch (_: Exception) {
                null
            }
            if (files != null) {
                return files
            }
        }
        return directory.listFiles().mapNotNull {
            val name = it.name?.takeIf(matches) ?: return@mapNotNull null
            SaveStateFile(it.uri, name, it.lastModified())
        }
    }

    private fun getSaveStateDirectoryDocument(rom: Rom): DocumentFile? {
        val saveStateDirectoryUri = settingsRepository.getSaveStateDirectory(rom) ?: return null
        return uriHandler.getUriTreeDocument(saveStateDirectoryUri)
    }

    private fun getRomFileNameWithoutExtension(rom: Rom): String? {
        val romDocument = uriHandler.getUriDocument(rom.uri)
        return romDocument?.nameWithoutExtension
    }
}
