package me.magnum.melonds.ui.dsiwaremanager

import android.net.Uri
import androidx.core.graphics.createBitmap
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import kotlinx.coroutines.CancellationException
import me.magnum.melonds.domain.model.DSiProfile
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.magnum.melonds.domain.model.ConfigurationDirResult
import me.magnum.melonds.domain.model.DSiWareTitle
import me.magnum.melonds.domain.model.dsinand.ImportDSiWareTitleResult
import me.magnum.melonds.domain.repositories.SettingsRepository
import me.magnum.melonds.domain.services.ConfigurationDirectoryVerifier
import me.magnum.melonds.domain.services.DSiNandManager
import me.magnum.melonds.ui.dsiwaremanager.model.DSiWareManagerUiState
import me.magnum.melonds.domain.model.dsinand.DSiWareTitleFileType
import me.magnum.melonds.ui.dsiwaremanager.model.ImportExportDSiWareTitleFileEvent
import me.magnum.melonds.ui.romlist.RomIcon
import java.nio.ByteBuffer
import javax.inject.Inject

@HiltViewModel
class DSiWareManagerViewModel @Inject constructor(
    private val dsiNandManager: DSiNandManager,
    private val settingsRepository: SettingsRepository,
    private val configurationDirectoryVerifier: ConfigurationDirectoryVerifier,
    private val savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val _state = MutableStateFlow<DSiWareManagerUiState>(DSiWareManagerUiState.Loading)
    val state: StateFlow<DSiWareManagerUiState> = _state

    private val _importingTitle = MutableStateFlow(false)
    val importingTitle: StateFlow<Boolean> = _importingTitle.asStateFlow()

    private val _importTitleError = MutableSharedFlow<ImportDSiWareTitleResult>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val importTitleError: SharedFlow<ImportDSiWareTitleResult> = _importTitleError.asSharedFlow()

    private val _importExportFileEvent = MutableSharedFlow<ImportExportDSiWareTitleFileEvent>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val importExportFileEvent: SharedFlow<ImportExportDSiWareTitleFileEvent> = _importExportFileEvent.asSharedFlow()

    val profiles = settingsRepository.observeDsiProfileSettings()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settingsRepository.getDsiProfileSettings())
    private val _selectedProfile = MutableStateFlow(settingsRepository.getDsiProfile(savedStateHandle["dsi_profile_id"]))
    val selectedProfile: StateFlow<DSiProfile?> = _selectedProfile.asStateFlow()

    init {
        revalidateBiosConfiguration()
    }

    fun selectProfile(profileId: String) {
        if (_importingTitle.value) return
        savedStateHandle["dsi_profile_id"] = profileId
        _selectedProfile.value = settingsRepository.getDsiProfile(profileId)
        revalidateBiosConfiguration()
    }

    fun prepareFileOperation() {
        savedStateHandle["pending_dsi_profile"] = _selectedProfile.value
    }

    private fun takeFileProfile(): DSiProfile? = savedStateHandle.remove("pending_dsi_profile")

    fun importTitleToNand(titleUri: Uri) {
        runOperation(takeFileProfile()) {
            val result = importTitle(titleUri)
            if (result != ImportDSiWareTitleResult.SUCCESS) _importTitleError.tryEmit(result)
        }
    }

    fun deleteTitle(title: DSiWareTitle) {
        runOperation(_selectedProfile.value) { deleteTitle(title) }
    }

    fun importDSiWareTitleFile(title: DSiWareTitle, fileType: DSiWareTitleFileType, fileUri: Uri) {
        runOperation(takeFileProfile()) {
            val success = importTitleFile(title, fileType, fileUri)
            _importExportFileEvent.tryEmit(if (success) ImportExportDSiWareTitleFileEvent.ImportSuccess(fileType.fileName) else ImportExportDSiWareTitleFileEvent.ImportError)
        }
    }

    fun exportDSiWareTitleFile(title: DSiWareTitle, fileType: DSiWareTitleFileType, fileUri: Uri) {
        runOperation(takeFileProfile()) {
            val success = exportTitleFile(title, fileType, fileUri)
            _importExportFileEvent.tryEmit(if (success) ImportExportDSiWareTitleFileEvent.ExportSuccess(fileType.fileName) else ImportExportDSiWareTitleFileEvent.ExportError)
        }
    }

    private fun runOperation(profile: DSiProfile?, operation: suspend DSiNandManager.() -> Unit) {
        if (_importingTitle.value) return
        _importingTitle.value = true
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val validation = configurationDirectoryVerifier.checkDsiConfigurationDirectory(profile)
                    if (validation.status != ConfigurationDirResult.Status.VALID) {
                        _state.value = DSiWareManagerUiState.DSiSetupInvalid(validation.status)
                        return@withContext
                    }
                    val configuration = settingsRepository.getEmulatorConfiguration(profile)
                    val titles = dsiNandManager.withNand(configuration) {
                        operation()
                        listTitles()
                    }
                    _state.value = titles?.let { DSiWareManagerUiState.Ready(it) } ?: DSiWareManagerUiState.Error
                }
            } catch (exception: Exception) {
                if (exception is CancellationException) throw exception
                _state.value = DSiWareManagerUiState.Error
            } finally {
                _importingTitle.value = false
            }
        }
    }

    fun getTitleIcon(title: DSiWareTitle): RomIcon {
        val bitmap = createBitmap(32, 32).apply {
            copyPixelsFromBuffer(ByteBuffer.wrap(title.icon))
        }
        val iconFiltering = settingsRepository.getRomIconFiltering()
        return RomIcon(bitmap, iconFiltering)
    }

    fun revalidateBiosConfiguration() {
        if (_importingTitle.value) return
        _selectedProfile.value = settingsRepository.getDsiProfile(savedStateHandle["dsi_profile_id"])
        _state.value = DSiWareManagerUiState.Loading
        runOperation(_selectedProfile.value) { }
    }
}
