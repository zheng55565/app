import { useInterstitialAdStore } from '@/stores/interstitialAd'

export function useBusinessAdTriggers() {
  const interstitial = useInterstitialAdStore()

  return {
    onRewardedAdCompleted: () => interstitial.show({ trigger: 'rewarded_ad_completed' }),
    onGameSettled: (gameId?: string) =>
      interstitial.show({ trigger: 'game_settlement', metadata: { game_id: gameId } }),
    onRedPacketClaimed: (packetId?: string) =>
      interstitial.show({ trigger: 'red_packet_claimed', metadata: { packet_id: packetId } }),
  }
}
