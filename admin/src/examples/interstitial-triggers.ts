// 在业务成功回调中调用；show 内部失败会被吞掉，不会中断原业务。
import { useBusinessAdTriggers } from '@/composables/useBusinessAdTriggers'

export async function afterRewardedAdCompleted() {
  const { onRewardedAdCompleted } = useBusinessAdTriggers()
  await onRewardedAdCompleted()
}

export async function afterGameSettled(gameRoundId: string) {
  const { onGameSettled } = useBusinessAdTriggers()
  await onGameSettled(gameRoundId)
}

export async function afterRedPacketClaimed(packetId: string) {
  const { onRedPacketClaimed } = useBusinessAdTriggers()
  await onRedPacketClaimed(packetId)
}
