import json
import async_timeout

from tests.test_checkin import create_users, join_user, checkin, send_message, \
        HAMBURG, MADRID


async def test_subscribe_room(cli):
    # create users, check in each and create a room by joining
    users = await create_users(cli, 2)
    await checkin(cli, users[0], HAMBURG)
    await checkin(cli, users[1], MADRID)
    room = await join_user(cli, users[0], users[1])

    # connect to websocket
    async with cli.ws_connect('/api/ws', headers={'Cookie': f'jwt={users[0]["jwt"]}'}) as ws:
        # subscribe to room and send a message
        await ws.send_str(json.dumps(dict(type='subscribe-room',
                                          data=dict(room_id=room['id']))))
        await send_message(cli, users[0], room, 'hey')

        # should receive new-messages
        async with async_timeout.timeout(1):
            async for msg in ws:
                data = json.loads(msg.data)
                assert data['type'] == 'new-messages'
                assert data['data']['messages'][0]['body'] == 'hey'
                break

        # test unsubscribe
        await ws.send_str(json.dumps(dict(type='unsubscribe-room',
                                          data=dict(room_id=room['id']))))

        # test signout
        await cli.post('/api/users/signout', cookies=dict(jwt=users[0]['jwt']))

        # close connection
        await ws.close()
