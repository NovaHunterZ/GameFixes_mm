/**
 * vim: set ts=4 sw=4 tw=99 noet:
 * =============================================================================
 * GameFixes_mm
 * Copyright (C) 2026 Michal "Slynx (˙·٠● S l y n x ●٠·˙)" Přikryl.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors:
 *   - Michal "Slynx (˙·٠● S l y n x ●٠·˙)" Přikryl
 *
 * Project: GameFixes_mm
 */

//====== Copyright © 1996-2005, Valve Corporation, All rights reserved. =======
//
// Purpose: The protobuf network messages the fixes look at
//
//=============================================================================

#ifndef SDK_NETMESSAGES_H
#define SDK_NETMESSAGES_H
#ifdef _WIN32
#pragma once
#endif

#include <netmessages.pb.h>
#include <networkbasetypes.pb.h>
#include <networksystem/inetchannel.h>
#include <networksystem/inetworkmessages.h>
#include <networksystem/inetworkserializer.h>
#include <networksystem_protomessages.pb.h>

#undef min
#undef max

// This file used to carry our own copies of the signon groups and typed
// message wrappers. After the Nov 11 2026 CS2 update the SDK ships those
// itself and the old copies stopped compiling. Nothing here used them anyway,
// so now this is just the includes the fixes need.

#endif // SDK_NETMESSAGES_H
