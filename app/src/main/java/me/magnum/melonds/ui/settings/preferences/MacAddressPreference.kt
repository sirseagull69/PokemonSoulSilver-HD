package me.magnum.melonds.ui.settings.preferences

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.widget.EditText
import androidx.core.widget.doAfterTextChanged
import androidx.appcompat.app.AlertDialog
import androidx.preference.Preference
import me.magnum.melonds.R
import me.magnum.melonds.databinding.DialogMacAddressEditorBinding
import me.magnum.melonds.domain.model.MacAddress
import kotlin.random.Random

class MacAddressPreference(context: Context, attrs: AttributeSet?) : Preference(context, attrs) {
    private val random = Random(System.nanoTime())

    override fun onClick() {
        super.onClick()

        val binding = DialogMacAddressEditorBinding.inflate(LayoutInflater.from(context))
        val currentMacAddress = getPersistedString(null)?.let { MacAddress.fromString(it) }
        setMacAddressText(currentMacAddress, binding.textMacAddress)
        binding.textMacAddress.doAfterTextChanged { binding.textMacAddress.error = null }

        val dialog = AlertDialog.Builder(context)
                .setTitle(title)
                .setView(binding.root)
                .setPositiveButton(R.string.ok, null)
                .setNegativeButton(R.string.cancel) { dialog, _ ->
                    dialog.dismiss()
                }
                .setNeutralButton(R.string.generate_new_mac_address, null)
                .show()

        // Set listener after creating dialog to prevent dismiss on click
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val address = MacAddress.fromString(binding.textMacAddress.text.toString().trim())
            if (address == null) {
                binding.textMacAddress.error = context.getString(R.string.invalid_mac_address)
                binding.textMacAddress.requestFocus()
            } else if (callChangeListener(address.toString())) {
                persistString(address.toString())
                dialog.dismiss()
            }
        }
        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
            setMacAddressText(MacAddress.randomDsAddress(random), binding.textMacAddress)
        }
    }

    private fun setMacAddressText(macAddress: MacAddress?, editor: EditText) {
        editor.setText(macAddress?.toString().orEmpty())
        editor.setSelection(editor.text.length)
    }
}
