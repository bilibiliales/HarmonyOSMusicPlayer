export class BubbleTip {
  static show(context: UIContext, message: string): void {
    const content = message.trim()
    if (!content) {
      return
    }
    context.getPromptAction().showToast({
      message: content,
      duration: 2200,
      bottom: '96vp'
    })
  }
}
