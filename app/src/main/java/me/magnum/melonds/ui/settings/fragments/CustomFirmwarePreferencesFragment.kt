package me.magnum.melonds.ui.settings.fragments

import android.net.Uri
import android.os.Bundle
import android.widget.EditText
import androidx.lifecycle.lifecycleScope
import androidx.preference.Preference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.magnum.melonds.common.Permission
import me.magnum.melonds.common.contracts.DirectoryPickerContract
import me.magnum.melonds.domain.model.DSiProfile
import me.magnum.melonds.domain.repositories.SettingsRepository
import java.util.UUID
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.viewModels
import androidx.preference.ListPreference
import dagger.hilt.android.AndroidEntryPoint
import me.magnum.melonds.R
import me.magnum.melonds.common.DirectoryAccessValidator
import me.magnum.melonds.common.UriPermissionManager
import me.magnum.melonds.domain.model.ConfigurationDirResult
import me.magnum.melonds.domain.model.ConsoleType
import me.magnum.melonds.ui.settings.viewmodel.CustomFirmwareViewModel
import me.magnum.melonds.ui.settings.PreferenceFragmentHelper
import me.magnum.melonds.ui.settings.PreferenceFragmentTitleProvider
import me.magnum.melonds.ui.settings.preferences.BiosDirectoryPickerPreference
import me.magnum.melonds.utils.enumValueOfIgnoreCase
import javax.inject.Inject

@AndroidEntryPoint
class CustomFirmwarePreferencesFragment : BasePreferenceFragment(), PreferenceFragmentTitleProvider {

    private val viewModel by viewModels<CustomFirmwareViewModel>()
    private val helper by lazy { PreferenceFragmentHelper(this, uriPermissionManager, directoryAccessValidator) }
    @Inject lateinit var uriPermissionManager: UriPermissionManager
    @Inject lateinit var directoryAccessValidator: DirectoryAccessValidator
    @Inject lateinit var settingsRepository: SettingsRepository

    private val profilePicker = registerForActivityResult(DirectoryPickerContract(Permission.READ_WRITE)) { uri ->
        if (uri != null) {
            lifecycleScope.launch {
                val valid = withContext(Dispatchers.IO) {
                    runCatching {
                        val status = viewModel.getConsoleConfigurationDirectoryStatus(ConsoleType.DSi, uri)
                        if (status.status != ConfigurationDirResult.Status.VALID) return@runCatching false
                        uriPermissionManager.persistDirectoryPermissions(uri, Permission.READ_WRITE)
                        true
                    }.getOrDefault(false)
                }
                if (valid) {
                    editProfileName(DSiProfile(UUID.randomUUID().toString(), "", uri.toString()))
                } else {
                    AlertDialog.Builder(requireContext()).setMessage(R.string.dsi_incorrect_bios_dir_info).setPositiveButton(R.string.ok, null).show()
                }
            }
        }
    }

    override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
        setPreferencesFromResource(R.xml.pref_custom_firmware, rootKey)
        val consoleTypePreference = findPreference<ListPreference>("console_type")!!
        val dsBiosDirPreference = findPreference<BiosDirectoryPickerPreference>("bios_dir")!!
        findPreference<Preference>("dsi_profiles")!!.setOnPreferenceClickListener {
            showProfiles()
            true
        }
        updateProfileSummary()

        helper.setupStoragePickerPreference(dsBiosDirPreference)

        val biosValidator = object : BiosDirectoryPickerPreference.BiosDirectoryValidator {
            override fun getBiosDirectoryValidationResult(consoleType: ConsoleType, directory: Uri?): ConfigurationDirResult {
                return viewModel.getConsoleConfigurationDirectoryStatus(consoleType, directory)
            }
        }

        dsBiosDirPreference.setBiosDirectoryValidator(biosValidator)

        consoleTypePreference.setOnPreferenceChangeListener { _, newValue ->
            val consoleTypePreferenceValue = newValue as String
            val newConsoleType = enumValueOfIgnoreCase<ConsoleType>(consoleTypePreferenceValue)

            if (viewModel.getConsoleConfigurationDirectoryStatus(newConsoleType).status != ConfigurationDirResult.Status.VALID) {
                val textRes = when (newConsoleType) {
                    ConsoleType.DS -> R.string.ds_incorrect_bios_dir_info
                    ConsoleType.DSi -> R.string.dsi_incorrect_bios_dir_info
                }

                AlertDialog.Builder(requireContext())
                        .setMessage(textRes)
                        .setPositiveButton(R.string.ok, null)
                        .show()
            }

            true
        }

        hideDependentsWhenInactive("use_custom_bios", "show_bios")
    }

    override fun onResume() {
        super.onResume()
        updateProfileSummary()
    }

    private fun updateProfileSummary() {
        findPreference<Preference>("dsi_profiles")?.summary = settingsRepository.getDsiProfile()?.name ?: getString(R.string.not_set)
    }

    private fun showProfiles() {
        val profiles = settingsRepository.getDsiProfileSettings()
        val labels = profiles.profiles.map {
            if (it.id == profiles.defaultProfileId) getString(R.string.dsi_profile_default_name, it.name) else it.name
        }
        AlertDialog.Builder(requireContext())
            .setTitle(R.string.dsi_profiles)
            .setItems(labels.toTypedArray()) { _, index -> showProfileActions(profiles.profiles[index]) }
            .setPositiveButton(R.string.dsi_profile_add) { _, _ -> profilePicker.launch(settingsRepository.getDsiBiosDirectory()) }
            .setNegativeButton(R.string.cancel, null)
            .show()
    }

    private fun showProfileActions(profile: DSiProfile) {
        val actions = arrayOf(getString(R.string.dsi_profile_make_default), getString(R.string.dsi_profile_rename), getString(R.string.action_remove))
        AlertDialog.Builder(requireContext())
            .setTitle(profile.name)
            .setItems(actions) { _, index ->
                when (index) {
                    0 -> { settingsRepository.setDefaultDsiProfile(profile.id); updateProfileSummary() }
                    1 -> editProfileName(profile)
                    2 -> AlertDialog.Builder(requireContext())
                        .setTitle(profile.name)
                        .setMessage(R.string.dsi_profile_remove_description)
                        .setPositiveButton(R.string.action_remove) { _, _ -> settingsRepository.removeDsiProfile(profile.id); updateProfileSummary() }
                        .setNegativeButton(R.string.cancel, null)
                        .show()
                }
            }
            .setNegativeButton(R.string.cancel, null)
            .show()
    }

    private fun editProfileName(profile: DSiProfile) {
        val input = EditText(requireContext()).apply {
            setSingleLine()
            setText(profile.name)
            hint = getString(R.string.dsi_profile_name)
            setPadding(32, 16, 32, 16)
        }
        val dialog = AlertDialog.Builder(requireContext())
            .setTitle(R.string.dsi_profile_name)
            .setView(input)
            .setPositiveButton(R.string.ok, null)
            .setNegativeButton(R.string.cancel, null)
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val name = input.text.toString().trim()
                if (name.isNotEmpty()) {
                    settingsRepository.saveDsiProfile(profile.copy(name = name))
                    updateProfileSummary()
                    dialog.dismiss()
                }
            }
        }
        dialog.show()
    }

    override fun getTitle() = getString(R.string.custom_bios_firmware)
}