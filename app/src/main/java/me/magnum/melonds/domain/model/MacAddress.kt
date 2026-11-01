package me.magnum.melonds.domain.model

import kotlin.random.Random
import kotlin.random.nextUBytes

data class MacAddress(private val addressBytes: List<UByte>) {
    companion object {
        private val DS_MAC_PREFIX = listOf(0x0.toUByte(), 0x9.toUByte(), 0xBF.toUByte())
        private val ADDRESS_PATTERN = Regex("[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}")

        fun fromString(address: String): MacAddress? {
            if (!ADDRESS_PATTERN.matches(address)) return null
            val bytes = address.split(":").map { it.toUByte(16) }
            return MacAddress(bytes)
        }

        fun randomDsAddress(random: Random? = null): MacAddress {
            val randomToUse = random ?: Random(System.nanoTime())
            val bytes = DS_MAC_PREFIX + randomToUse.nextUBytes(3).toList()
            return MacAddress(bytes)
        }
    }

    fun isValid(): Boolean {
        return addressBytes.size == 6
    }

    /**
     * Returns the string representation of the MAC address. The string contains the 6 address bytes represented in hexadecimal format, each one separated by a colon.
     */
    override fun toString(): String {
        return addressBytes.joinToString(":") { it.toString(16).padStart(2, '0') }.uppercase()
    }
}
