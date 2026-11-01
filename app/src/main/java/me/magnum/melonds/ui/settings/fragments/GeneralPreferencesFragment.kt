package me.magnum.melonds.ui.settings.fragments

import android.os.Bundle
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.lifecycle.lifecycleScope
import androidx.preference.ListPreference
import androidx.preference.Preference
import androidx.preference.PreferenceManager
import androidx.preference.SwitchPreference
import androidx.preference.TwoStatePreference
import com.smp.masterswitchpreference.MasterSwitchPreference
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.magnum.melonds.R
import me.magnum.melonds.common.DirectoryAccessValidator
import me.magnum.melonds.common.UriPermissionManager
import me.magnum.melonds.extensions.isSustainedPerformanceModeAvailable
import me.magnum.melonds.impl.SettingsBackupManager
import me.magnum.melonds.ui.common.LauncherIcon
import me.magnum.melonds.ui.settings.PreferenceFragmentHelper
import me.magnum.melonds.ui.settings.PreferenceFragmentTitleProvider
import me.magnum.melonds.ui.settings.preferences.StoragePickerPreference
import me.magnum.melonds.extensions.addOnPreferenceChangeListener
import javax.inject.Inject

@AndroidEntryPoint
class GeneralPreferencesFragment : BasePreferenceFragment(), PreferenceFragmentTitleProvider {

    private val helper by lazy { PreferenceFragmentHelper(this, uriPermissionManager, directoryAccessValidator) }
    @Inject lateinit var uriPermissionManager: UriPermissionManager
    @Inject lateinit var directoryAccessValidator: DirectoryAccessValidator
    @Inject lateinit var settingsBackupManager: SettingsBackupManager

    private lateinit var rewindPreference: MasterSwitchPreference
    private lateinit var frameLimitSpeedPreference: ListPreference
    private var iconUpdate: Job? = null

    private val backupLauncher = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            lifecycleScope.launch(Dispatchers.IO) {
                runCatching { settingsBackupManager.backup(uri) }
                    .onSuccess {
                        withContext(Dispatchers.Main) {
                            AlertDialog.Builder(requireContext())
                                .setMessage(R.string.settings_backup_success)
                                .setPositiveButton(android.R.string.ok, null)
                                .show()
                        }
                    }
                    .onFailure {
                        withContext(Dispatchers.Main) {
                            Toast.makeText(requireContext(), R.string.settings_backup_error, Toast.LENGTH_SHORT).show()
                        }
                    }
            }
        }
    }

    private val restoreLauncher = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            lifecycleScope.launch(Dispatchers.IO) {
                runCatching { settingsBackupManager.restore(uri) }
                    .onSuccess {
                        withContext(Dispatchers.Main) {
                            AlertDialog.Builder(requireContext())
                                .setMessage(R.string.settings_restore_success)
                                .setPositiveButton(android.R.string.ok, null)
                                .show()
                        }
                    }
                    .onFailure {
                        withContext(Dispatchers.Main) {
                            Toast.makeText(requireContext(), R.string.settings_restore_error, Toast.LENGTH_SHORT).show()
                        }
                    }
            }
        }
    }

    override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
        setPreferencesFromResource(R.xml.pref_general, rootKey)
        addPreferencesFromResource(R.xml.pref_general_updates)

        rewindPreference = findPreference("enable_rewind")!!
        frameLimitSpeedPreference = findPreference("frame_limit_speed_multiplier")!!
        val sustainedPerformancePreference = findPreference<SwitchPreference>("enable_sustained_performance")!!

        helper.bindPreferenceSummaryToValue(rewindPreference)
        helper.bindPreferenceSummaryToValue(frameLimitSpeedPreference)
        val screenshotDirectory = findPreference<StoragePickerPreference>("screenshot_directory")!!
        helper.setupStoragePickerPreference(screenshotDirectory)
        screenshotDirectory.addOnPreferenceChangeListener { _, value ->
            if ((value as? Set<*>)?.isNotEmpty() != true) {
                screenshotDirectory.summary = getString(R.string.screenshot_directory_default)
            }
            true
        }
        if (screenshotDirectory.getPersistedStringSet(null).isNullOrEmpty()) {
            screenshotDirectory.summary = getString(R.string.screenshot_directory_default)
        }
        updateFrameLimitSpeedPreferenceState()
        sustainedPerformancePreference.isVisible = requireContext().isSustainedPerformanceModeAvailable()

        frameLimitSpeedPreference.sharedPreferences?.registerOnSharedPreferenceChangeListener(sharedPreferenceChangeListener)

        findPreference<Preference>("backup_settings")?.setOnPreferenceClickListener {
            backupLauncher.launch(null)
            true
        }
        findPreference<Preference>("restore_settings")?.setOnPreferenceClickListener {
            restoreLauncher.launch(null)
            true
        }
        findPreference<TwoStatePreference>("use_alt_app_icon")?.setOnPreferenceChangeListener { _, value ->
            updateIcon(value as Boolean)
            false
        }
    }

    override fun onResume() {
        super.onResume()
        // Set proper value for Rewind preference since the value is not updated when returning from the fragment
        rewindPreference.onPreferenceChangeListener?.onPreferenceChange(rewindPreference, rewindPreference.sharedPreferences?.getBoolean(rewindPreference.key, false))
        updateFrameLimitSpeedPreferenceState()
        updateIcon()
    }

    override fun onDestroy() {
        frameLimitSpeedPreference.sharedPreferences?.unregisterOnSharedPreferenceChangeListener(sharedPreferenceChangeListener)
        super.onDestroy()
    }

    override fun getTitle() = getString(R.string.category_general)

    private fun updateIcon(alternative: Boolean? = null) {
        if (iconUpdate?.isActive == true) return
        val preference = findPreference<TwoStatePreference>("use_alt_app_icon") ?: return
        val context = requireContext().applicationContext
        preference.isEnabled = false
        iconUpdate = viewLifecycleOwner.lifecycleScope.launch {
            try {
                var changeFailed = false
                preference.isChecked = withContext(Dispatchers.IO) {
                    if (alternative != null) {
                        try {
                            LauncherIcon.setAlternative(context, alternative)
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (_: Exception) {
                            changeFailed = true
                        }
                    }
                    LauncherIcon.isAlternative(context)
                }
                if (changeFailed) {
                    Toast.makeText(context, R.string.app_icon_change_failed, Toast.LENGTH_LONG).show()
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                Toast.makeText(context, R.string.app_icon_change_failed, Toast.LENGTH_LONG).show()
            } finally {
                preference.isEnabled = true
            }
        }
    }

    private val sharedPreferenceChangeListener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "ra_hardcore_enabled" || key == frameLimitSpeedPreference.key) {
            updateFrameLimitSpeedPreferenceState()
        }
    }

    private fun updateFrameLimitSpeedPreferenceState() {
        val preferences = PreferenceManager.getDefaultSharedPreferences(requireContext())
        val hardcoreEnabled = preferences.getBoolean("ra_hardcore_enabled", false)
        frameLimitSpeedPreference.isVisible = !hardcoreEnabled
        if (!hardcoreEnabled) {
            frameLimitSpeedPreference.summary = frameLimitSpeedPreference.entry ?: getString(R.string.not_set)
        }
    }
}
