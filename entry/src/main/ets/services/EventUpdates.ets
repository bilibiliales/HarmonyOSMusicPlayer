import { UserEventItem } from '../models/api'

type EventUpdateListener = (event: UserEventItem, deleted: boolean) => void

// Keep already mounted feeds in sync without reloading their content or scroll position.
export class EventUpdates {
  private static listeners: Set<EventUpdateListener> = new Set()

  static subscribe(listener: EventUpdateListener): () => void {
    EventUpdates.listeners.add(listener)
    return () => { EventUpdates.listeners.delete(listener) }
  }

  static publish(event: UserEventItem, deleted: boolean): void {
    EventUpdates.listeners.forEach((listener: EventUpdateListener) => listener(event, deleted))
  }
}
