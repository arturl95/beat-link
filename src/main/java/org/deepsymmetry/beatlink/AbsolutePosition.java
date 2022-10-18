package org.deepsymmetry.beatlink;

import java.net.DatagramPacket;

/**
 * A device update that announces the start of a new beat on a DJ Link network.
 * Even though beats contain far less detailed information than status updates,
 * they can be passed to {@link VirtualCdj#getLatestStatusFor(DeviceUpdate)} to
 * find the current detailed status for that device, as long as the Virtual CDJ
 * is active.
 *
 * They also provide information about the timing of a variety upcoming beats
 * and bars, which may be helpful for implementing Sync in a player, but the
 * full {@link org.deepsymmetry.beatlink.data.BeatGrid} can be obtained as well.
 *
 * @author James Elliott
 */
@SuppressWarnings("WeakerAccess")
public class AbsolutePosition extends DeviceUpdate {

	long position;
	private int pitch;
	private int bpm;

	/**
	 * Constructor sets all the immutable interpreted fields based on the packet
	 * content.
	 *
	 * @param packet the beat announcement packet that was received
	 */
	public AbsolutePosition(DatagramPacket packet) {
		super(packet, "Absolute position announcement", 0x3C);
		position = Util.bytesToNumber(getPacketBytes(), 0x28, 4);
		pitch = (int)Util.bytesToNumber(packetBytes, 0x2C, 4);
        bpm = (int)Util.bytesToNumber(packetBytes, 0x38, 4);
	}

	@Override
	public String toString() {
		return "AbsolutePosition: Device " + getDeviceNumber() + ", name: " + getDeviceName() + ", position: "
				+ position;
	}

	/**
	 * Was this beat sent by the current tempo master?
	 *
	 * @return {@code true} if the device that sent this beat is the master
	 * @throws IllegalStateException if the {@link VirtualCdj} is not running
	 */
	@Override
	public boolean isTempoMaster() {
		DeviceUpdate master = VirtualCdj.getInstance().getTempoMaster();
		return (master != null) && master.getAddress().equals(getAddress())
				&& master.getDeviceNumber() == getDeviceNumber();
	}

	/**
	 * Was this beat sent by a device that is synced to the tempo master?
	 *
	 * @return {@code true} if the device that sent this beat is synced
	 * @throws IllegalStateException if the {@link VirtualCdj} is not running
	 */
	@Override
	public boolean isSynced() {
		return VirtualCdj.getInstance().getLatestStatusFor(this).isSynced();
	}

	@SuppressWarnings("SameReturnValue")
	@Override
	public Integer getDeviceMasterIsBeingYieldedTo() {
		return null; // Beats never yield the master role
	}

	@Override
	public double getEffectiveTempo() {
		return bpm * Util.pitchToMultiplier(pitch) / 100.0;
	}

	public long getPosition() {
		return position;
	}

	@Override
	public int getBeatWithinBar() {
		// TODO Auto-generated method stub
		return -1;
	}

	@Override
	public boolean isBeatWithinBarMeaningful() {
		// TODO Auto-generated method stub
		return false;
	}

	@Override
	public int getPitch() {
		// TODO Auto-generated method stub
		return pitch;
	}

	@Override
	public int getBpm() {
		// TODO Auto-generated method stub
		return bpm;
	}

}
