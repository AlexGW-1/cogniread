import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { extractUserIdFromAuthHeader } from './auth.util';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const userId = extractUserIdFromAuthHeader(request.headers?.authorization);
    if (!userId) {
      throw new UnauthorizedException('Missing or invalid bearer token');
    }
    request.userId = userId;
    return true;
  }
}
